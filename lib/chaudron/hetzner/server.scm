;;; Hetzner Cloud servers.

(define-module (chaudron hetzner server)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:use-module (chaudron hetzner firewall)
  #:use-module (chaudron hetzner primary-ip)
  #:use-module (chaudron hetzner volume)
  #:use-module (ice-9 match)
  #:export (hetzner-server))

(define* (server-action id action #:optional body)
  (resource-action "servers" id action body))

(define (server-outputs server)
  `((id . ,(json-ref server "id"))
    (ipv4 . ,(json-ref server "public_net" "ipv4" "ip"))
    (ipv6 . ,(json-ref server "public_net" "ipv6" "ip"))
    (private-ipv4 . ,(match (json-list server "private_net")
                       ((network . _) (json-ref network "ip"))
                       (() #f)))
    (ipv4-id . ,(json-ref server "public_net" "ipv4" "id"))
    (ipv6-id . ,(json-ref server "public_net" "ipv6" "id"))))

(define (fetch-server-outputs id)
  (server-outputs (json-ref (hetzner-request 'GET (resource-path "servers" id))
                            "server")))

(define (create-server _ props)
  (define (ids key)
    (list->vector (list-prop props key)))
  (define (primary-ip family)
    (if (assq-ref props family)
        `((,(symbol->string family) . ,(assq-ref props family)))
        '()))

  (let* ((response (hetzner-request
                    'POST "/servers"
                    `(("name" . ,(assq-ref props 'name))
                      ("server_type" . ,(assq-ref props 'type))
                      ("location" . ,(assq-ref props 'location))
                      ("image" . ,(assq-ref props 'image))
                      ("ssh_keys" . ,(ids 'ssh-keys))
                      ("firewalls"
                       . ,(list->vector
                           (map (lambda (id) `(("firewall" . ,id)))
                                (list-prop props 'firewalls))))
                      ("volumes" . ,(ids 'volumes))
                      ,@(if (pair? (list-prop props 'volumes))
                            '(("automount" . #t))
                            '())
                      ("networks" . ,(ids 'networks))
                      ("public_net" . (,@(primary-ip 'ipv4)
                                       ,@(primary-ip 'ipv6)))
                      ,@(if (assq-ref props 'user-data)
                            `(("user_data" . ,(assq-ref props 'user-data)))
                            '())
                      ("labels" . ,(labels->json props)))))
         (outputs (server-outputs (json-ref response "server")))
         (id (assq-ref outputs 'id)))
    (created! outputs props '((backups? . #f) (protected? . #f)))
    (wait-for-actions response)
    (when (assq-ref props 'backups?)
      (server-action id "enable_backup"))
    (when (assq-ref props 'protected?)
      (protect! "servers" id props #:rebuild? #t))
    outputs))

;; The API does not report everything a server was created with, such as
;; its image or SSH keys; only what it does report is checked for drift.
(define (read-server outputs)
  (and=> (json-ref (hetzner-get (resource-path "servers" (assq-ref outputs 'id)))
                   "server")
         (lambda (server)
           (cons `(,@(observe-metadata server)
                   (type . ,(json-ref server "server_type" "name"))
                   (backups? . ,(string? (json-ref server "backup_window")))
                   ,@(observe-protection server))
                 (server-outputs server)))))

(define (update-server outputs old new)
  (define (changed? key)
    (not (equal? (assq-ref old key) (assq-ref new key))))
  (define (sync! key add! remove!)
    (sync-lists! (list-prop old key) (list-prop new key) add! remove!))
  (define id (assq-ref outputs 'id))

  (update-metadata! "servers" id old new)
  (update-protection! "servers" id old new #:rebuild? #t)
  (when (changed? 'backups?)
    (server-action id (if (assq-ref new 'backups?)
                          "enable_backup"
                          "disable_backup")))
  (when (or (changed? 'type) (changed? 'ipv4) (changed? 'ipv6))
    ;; These changes require the server to be off.
    (server-action id "poweroff")
    (when (changed? 'type)
      ;; The disk is left as is, so that the server can be downgraded again.
      (server-action id "change_type"
                     `(("server_type" . ,(assq-ref new 'type))
                       ("upgrade_disk" . #f))))
    (when (changed? 'ipv4) (swap-primary-ip! outputs 'ipv4 old new))
    (when (changed? 'ipv6) (swap-primary-ip! outputs 'ipv6 old new))
    (server-action id "poweron"))
  (sync! 'firewalls
         (lambda (firewall) (apply-firewall! firewall id))
         (lambda (firewall) (remove-firewall! firewall id)))
  (sync! 'volumes
         (lambda (volume) (attach-volume! volume id))
         detach-volume!)
  (sync! 'networks
         (lambda (network)
           (server-action id "attach_to_network" `(("network" . ,network))))
         (lambda (network)
           (server-action id "detach_from_network" `(("network" . ,network)))))
  (when (or (changed? 'ssh-keys) (changed? 'user-data))
    (report "~a: ssh-keys and user-data only apply when a server is created"
            (assq-ref new 'name)))
  (if (or (changed? 'ipv4) (changed? 'ipv6)
          (not (equal? (list-prop old 'networks) (list-prop new 'networks))))
      (fetch-server-outputs id)
      outputs))

(define (delete-server outputs)
  (and=> (hetzner-delete (resource-path "servers" (assq-ref outputs 'id)))
         wait-for-actions))

(define server-provider
  (register-provider!
   (make-provider 'hetzner-server
                  #:create create-server
                  #:read read-server
                  #:update update-server
                  #:delete delete-server
                  #:replace-on '(location image))))

(define* (hetzner-server resource-name
                         #:key type location (image "debian-12")
                         (ssh-keys '()) (firewalls '()) (volumes '())
                         (networks '()) ipv4 ipv6 user-data backups?
                         (labels '()) protected? name)
  "Declare a server.  Changing LOCATION or IMAGE replaces it, losing the
data on its disk; everything else changes in place.  IPV4 and IPV6 are
primary IPs, by default new ones are made; changing TYPE, IPV4 or IPV6
reboots the server.  SSH-KEYS and USER-DATA, a cloud-init configuration,
are only used when the server is created."
  (unless (and type location)
    (error "hetzner-server: #:type and #:location are required" resource-name))
  (ensure-resource server-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (type . ,type)
                     (location . ,location)
                     (image . ,image)
                     (ssh-keys . ,ssh-keys)
                     (firewalls . ,firewalls)
                     (volumes . ,volumes)
                     (networks . ,networks)
                     (ipv4 . ,ipv4)
                     (ipv6 . ,ipv6)
                     (user-data . ,user-data)
                     (backups? . ,(and backups? #t))
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))
