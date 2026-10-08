;;; Hetzner Cloud servers.

(define-module (chaudron hetzner server)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (srfi srfi-1)
  #:export (hetzner-server))

(define (server-path outputs . rest)
  (apply string-append "/servers/" (number->string (assq-ref outputs 'id))
         rest))

(define* (server-action outputs action #:optional body)
  (wait-for-action
   (json-ref (hetzner-request 'POST (server-path outputs "/actions/" action)
                              body)
             "action")))

(define (server-outputs server)
  `((id . ,(json-ref server "id"))
    (ipv4 . ,(json-ref server "public_net" "ipv4" "ip"))
    (ipv6 . ,(json-ref server "public_net" "ipv6" "ip"))))

(define (create-server _ props)
  (let ((response (hetzner-request
                   'POST "/servers"
                   `(("name" . ,(assq-ref props 'name))
                     ("server_type" . ,(assq-ref props 'type))
                     ("location" . ,(assq-ref props 'location))
                     ("image" . ,(assq-ref props 'image))
                     ("ssh_keys" . ,(list->vector (assq-ref props 'ssh-keys)))
                     ("firewalls"
                      . ,(list->vector
                          (map (lambda (id) `(("firewall" . ,id)))
                               (assq-ref props 'firewalls))))
                     ,@(if (assq-ref props 'user-data)
                           `(("user_data" . ,(assq-ref props 'user-data)))
                           '())
                     ("labels" . ,(stage-labels))))))
    (wait-for-action (json-ref response "action"))
    (for-each wait-for-action
              (vector->list (or (json-ref response "next_actions") #())))
    (server-outputs (json-ref response "server"))))

;; Only the name and type are checked for drift: they are the only props
;; that can change in place, and the API does not report the others.
(define (read-server outputs)
  (and=> (json-ref (hetzner-get (server-path outputs)) "server")
         (lambda (server)
           (cons `((name . ,(json-ref server "name"))
                   (type . ,(json-ref server "server_type" "name")))
                 (server-outputs server)))))

(define (attach-firewall! outputs firewall attach?)
  (let ((server `(("type" . "server")
                  ("server" . (("id" . ,(assq-ref outputs 'id)))))))
    (wait-for-actions
     (hetzner-request
      'POST (format #f "/firewalls/~a/actions/~a" firewall
                    (if attach? "apply_to_resources" "remove_from_resources"))
      `((,(if attach? "apply_to" "remove_from") . ,(vector server)))))))

(define (update-server outputs old new)
  (define (changed? key)
    (not (equal? (assq-ref old key) (assq-ref new key))))
  (define (firewalls props)
    (or (assq-ref props 'firewalls) '()))

  (when (changed? 'name)
    (hetzner-request 'PUT (server-path outputs)
                     `(("name" . ,(assq-ref new 'name)))))
  (when (changed? 'type)
    ;; Resizing requires the server to be off.  The disk is left as is, so
    ;; that the server can be downgraded again later.
    (server-action outputs "poweroff")
    (server-action outputs "change_type"
                   `(("server_type" . ,(assq-ref new 'type))
                     ("upgrade_disk" . #f)))
    (server-action outputs "poweron"))
  (for-each (lambda (id) (attach-firewall! outputs id #f))
            (lset-difference = (firewalls old) (firewalls new)))
  (for-each (lambda (id) (attach-firewall! outputs id #t))
            (lset-difference = (firewalls new) (firewalls old)))
  (when (or (changed? 'ssh-keys) (changed? 'user-data))
    (report "~a: ssh-keys and user-data only apply when a server is created"
            (assq-ref new 'name)))
  outputs)

(define (delete-server outputs)
  (and=> (hetzner-delete (server-path outputs))
         (lambda (response)
           (wait-for-action (json-ref response "action")))))

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
                         (ssh-keys '()) (firewalls '()) user-data
                         (name resource-name))
  "Declare a server.  Changing TYPE resizes it in place and FIREWALLS are
attached and detached as needed.  Changing LOCATION or IMAGE replaces it,
losing its data.  SSH-KEYS and USER-DATA, a cloud-init configuration, are
only used when the server is created."
  (unless (and type location)
    (error "hetzner-server: #:type and #:location are required" resource-name))
  (ensure-resource server-provider resource-name
                   `((name . ,name)
                     (type . ,type)
                     (location . ,location)
                     (image . ,image)
                     (ssh-keys . ,ssh-keys)
                     (firewalls . ,firewalls)
                     (user-data . ,user-data))))
