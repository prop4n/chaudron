;;; Hetzner Cloud private networks.

(define-module (chaudron hetzner network)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:export (hetzner-network))

(define (subnet->json zone ip-range)
  `(("type" . "cloud") ("network_zone" . ,zone) ("ip_range" . ,ip-range)))

(define (create-network _ props)
  (let* ((zone (assq-ref props 'zone))
         (response (hetzner-request
                    'POST "/networks"
                    `(("name" . ,(assq-ref props 'name))
                      ("ip_range" . ,(assq-ref props 'ip-range))
                      ("subnets"
                       . ,(list->vector
                           (map (lambda (subnet) (subnet->json zone subnet))
                                (assq-ref props 'subnets))))
                      ("labels" . ,(labels->json props)))))
         (id (json-ref response "network" "id")))
    (created! `((id . ,id)) props '((protected? . #f)))
    (when (assq-ref props 'protected?)
      (protect! "networks" id props))
    `((id . ,id))))

(define (read-network outputs)
  (and=> (json-ref (hetzner-get (resource-path "networks" (assq-ref outputs 'id)))
                   "network")
         (lambda (network)
           (cons `(,@(observe-metadata network)
                   (ip-range . ,(json-ref network "ip_range"))
                   (subnets . ,(sort (map (lambda (subnet)
                                            (json-ref subnet "ip_range"))
                                          (json-list network "subnets"))
                                     string<?))
                   ,@(observe-protection network))
                 outputs))))

(define (update-network outputs old new)
  (let ((id (assq-ref outputs 'id)))
    (define (subnet-action! action ip-range)
      (resource-action "networks" id action
                       (if (string=? action "add_subnet")
                           (subnet->json (assq-ref new 'zone) ip-range)
                           `(("ip_range" . ,ip-range)))))

    (update-metadata! "networks" id old new)
    (update-protection! "networks" id old new)
    (unless (equal? (assq-ref old 'ip-range) (assq-ref new 'ip-range))
      (resource-action "networks" id "change_ip_range"
                       `(("ip_range" . ,(assq-ref new 'ip-range)))))
    (sync-lists! (list-prop old 'subnets) (list-prop new 'subnets)
                 (lambda (subnet) (subnet-action! "add_subnet" subnet))
                 (lambda (subnet) (subnet-action! "delete_subnet" subnet))))
  outputs)

(define (delete-network outputs)
  (hetzner-delete (resource-path "networks" (assq-ref outputs 'id))))

(define network-provider
  (register-provider!
   (make-provider 'hetzner-network
                  #:create create-network
                  #:read read-network
                  #:update update-network
                  #:delete delete-network
                  #:replace-on '(zone))))

(define* (hetzner-network resource-name
                          #:key (ip-range "10.0.0.0/16") subnets
                          (zone "eu-central") (labels '()) protected?
                          name)
  "Declare a private network covering IP-RANGE, with SUBNETS (by default,
the whole range) in network ZONE.  Give it to servers with their #:networks
argument.  IP-RANGE can only grow."
  (ensure-resource network-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (ip-range . ,ip-range)
                     (zone . ,zone)
                     (subnets . ,(sort (or subnets (list ip-range)) string<?))
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))
