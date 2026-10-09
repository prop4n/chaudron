;;; Hetzner Cloud load balancers.

(define-module (chaudron hetzner load-balancer)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:use-module (srfi srfi-1)
  #:export (forward
            hetzner-load-balancer))

(define* (forward protocol port #:key (to port))
  "Return a service forwarding PROTOCOL traffic, 'tcp or 'http, from PORT
on the load balancer to port TO on its targets."
  `((protocol . ,(symbol->string protocol))
    (listen-port . ,port)
    (destination-port . ,to)))

(define (service->json service)
  `(("protocol" . ,(assq-ref service 'protocol))
    ("listen_port" . ,(assq-ref service 'listen-port))
    ("destination_port" . ,(assq-ref service 'destination-port))))

(define (target->json props server)
  `(("type" . "server")
    ("server" . (("id" . ,server)))
    ,@(if (assq-ref props 'network) '(("use_private_ip" . #t)) '())))

(define (load-balancer-outputs lb)
  `((id . ,(json-ref lb "id"))
    (ipv4 . ,(json-ref lb "public_net" "ipv4" "ip"))
    (ipv6 . ,(json-ref lb "public_net" "ipv6" "ip"))))

(define (create-load-balancer _ props)
  (let* ((response (hetzner-request
                    'POST "/load_balancers"
                    `(("name" . ,(assq-ref props 'name))
                      ("load_balancer_type" . ,(assq-ref props 'type))
                      ("location" . ,(assq-ref props 'location))
                      ("algorithm" . (("type" . ,(assq-ref props 'algorithm))))
                      ("services"
                       . ,(list->vector (map service->json
                                             (assq-ref props 'services))))
                      ("targets"
                       . ,(list->vector (map (lambda (server)
                                               (target->json props server))
                                             (assq-ref props 'targets))))
                      ,@(if (assq-ref props 'network)
                            `(("network" . ,(assq-ref props 'network)))
                            '())
                      ("labels" . ,(labels->json props)))))
         (outputs (load-balancer-outputs (json-ref response "load_balancer"))))
    (wait-for-actions response)
    (when (assq-ref props 'protected?)
      (protect! "load_balancers" (assq-ref outputs 'id) props))
    outputs))

(define (read-load-balancer outputs)
  (and=> (json-ref (hetzner-get (resource-path "load_balancers"
                                               (assq-ref outputs 'id)))
                   "load_balancer")
         (lambda (lb)
           (cons `(,@(observe-metadata lb)
                   (type . ,(json-ref lb "load_balancer_type" "name"))
                   (algorithm . ,(json-ref lb "algorithm" "type"))
                   ,@(observe-protection lb))
                 (load-balancer-outputs lb)))))

(define (update-services! id old new)
  "Delete, update and add services so that OLD services become NEW ones.
Services are identified by their listen port."
  (define (port service) (assq-ref service 'listen-port))
  (define (find-port services port*)
    (find (lambda (service) (= (port service) port*)) services))

  (for-each (lambda (service)
              (unless (find-port new (port service))
                (resource-action "load_balancers" id "delete_service"
                                 `(("listen_port" . ,(port service))))))
            old)
  (for-each (lambda (service)
              (let ((current (find-port old (port service))))
                (cond ((not current)
                       (resource-action "load_balancers" id "add_service"
                                        (service->json service)))
                      ((not (equal? current service))
                       (resource-action "load_balancers" id "update_service"
                                        (service->json service))))))
            new))

(define (update-load-balancer outputs old new)
  (define (changed? key)
    (not (equal? (assq-ref old key) (assq-ref new key))))
  (define (target-action! action)
    (lambda (server)
      (resource-action "load_balancers" id action (target->json new server))))
  (define id (assq-ref outputs 'id))

  (update-metadata! "load_balancers" id old new)
  (update-protection! "load_balancers" id old new)
  (when (changed? 'type)
    (resource-action "load_balancers" id "change_type"
                     `(("load_balancer_type" . ,(assq-ref new 'type)))))
  (when (changed? 'algorithm)
    (resource-action "load_balancers" id "change_algorithm"
                     `(("type" . ,(assq-ref new 'algorithm)))))
  (update-services! id (list-prop old 'services) (list-prop new 'services))
  (sync-lists! (list-prop old 'targets) (list-prop new 'targets)
               (target-action! "add_target")
               (target-action! "remove_target"))
  outputs)

(define (delete-load-balancer outputs)
  (hetzner-delete (resource-path "load_balancers" (assq-ref outputs 'id))))

(define load-balancer-provider
  (register-provider!
   (make-provider 'hetzner-load-balancer
                  #:create create-load-balancer
                  #:read read-load-balancer
                  #:update update-load-balancer
                  #:delete delete-load-balancer
                  #:replace-on '(location network))))

(define* (hetzner-load-balancer resource-name
                                #:key (type "lb11") location
                                (algorithm 'round-robin) (services '())
                                (targets '()) network (labels '()) protected?
                                name)
  "Declare a load balancer in LOCATION, sending the traffic of SERVICES,
built with `forward', to TARGETS, a list of servers.  With NETWORK, it
reaches them through that private network."
  (unless location
    (error "hetzner-load-balancer: #:location is required" resource-name))
  (ensure-resource load-balancer-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (type . ,type)
                     (location . ,location)
                     (algorithm . ,(case algorithm
                                     ((round-robin) "round_robin")
                                     ((least-connections) "least_connections")
                                     (else (error "unknown algorithm"
                                                  algorithm))))
                     (services . ,services)
                     (targets . ,targets)
                     (network . ,network)
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))
