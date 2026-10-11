;;; Hetzner Cloud primary IPs: public addresses that outlive servers.

(define-module (chaudron hetzner primary-ip)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:export (hetzner-primary-ip
            swap-primary-ip!))

(define (primary-ip-outputs ip)
  `((id . ,(json-ref ip "id"))
    (ip . ,(json-ref ip "ip"))))

(define (create-primary-ip _ props)
  (let* ((response (hetzner-request 'POST "/primary_ips"
                                    `(("name" . ,(assq-ref props 'name))
                                      ("type" . ,(assq-ref props 'type))
                                      ("location" . ,(assq-ref props 'location))
                                      ("assignee_type" . "unassigned")
                                      ("auto_delete" . #f)
                                      ("labels" . ,(labels->json props)))))
         (outputs (primary-ip-outputs (json-ref response "primary_ip"))))
    (created! outputs props '((protected? . #f)))
    (wait-for-actions response)
    (when (assq-ref props 'protected?)
      (protect! "primary_ips" (assq-ref outputs 'id) props))
    outputs))

(define (read-primary-ip outputs)
  (and=> (json-ref (hetzner-get (resource-path "primary_ips"
                                               (assq-ref outputs 'id)))
                   "primary_ip")
         (lambda (ip)
           (cons (append (observe-metadata ip) (observe-protection ip))
                 (primary-ip-outputs ip)))))

(define (update-primary-ip outputs old new)
  (let ((id (assq-ref outputs 'id)))
    (update-metadata! "primary_ips" id old new)
    (update-protection! "primary_ips" id old new))
  outputs)

(define (delete-primary-ip outputs)
  (hetzner-delete (resource-path "primary_ips" (assq-ref outputs 'id))))

(define primary-ip-provider
  (register-provider!
   (make-provider 'hetzner-primary-ip
                  #:create create-primary-ip
                  #:read read-primary-ip
                  #:update update-primary-ip
                  #:delete delete-primary-ip
                  #:replace-on '(type location))))

(define* (hetzner-primary-ip resource-name
                             #:key (type 'ipv4) location (labels '())
                             protected? name)
  "Declare a public IP address of TYPE, 'ipv4 or 'ipv6, in LOCATION.  Give
it to a server with its #:ipv4 or #:ipv6 argument: the server can then be
replaced without changing address."
  (unless location
    (error "hetzner-primary-ip: #:location is required" resource-name))
  (ensure-resource primary-ip-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (type . ,(symbol->string type))
                     (location . ,location)
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))

;;; Changing the primary IPs of servers.

(define (swap-primary-ip! outputs family old new)
  "Give the powered-off server of OUTPUTS the FAMILY ('ipv4 or 'ipv6) primary
IP of its NEW props, or a new automatic one if it has none.  OLD are its
previous props."
  (let ((id (assq-ref outputs 'id))
        (current (assq-ref outputs (symbol-append family '-id)))
        (wanted (assq-ref new family)))
    (when current
      (resource-action "primary_ips" current "unassign")
      (unless (assq-ref old family)
        ;; Created automatically along with the server: nobody else uses it.
        (hetzner-delete (resource-path "primary_ips" current))))
    (if wanted
        (resource-action "primary_ips" wanted "assign"
                         `(("assignee_type" . "server") ("assignee_id" . ,id)))
        (wait-for-actions
         (hetzner-request 'POST "/primary_ips"
                          `(("name" . ,(format #f "~a-~a" (assq-ref new 'name)
                                               family))
                            ("type" . ,(symbol->string family))
                            ("assignee_type" . "server")
                            ("assignee_id" . ,id)
                            ("auto_delete" . #t)
                            ("labels" . ,(labels->json '()))))))))
