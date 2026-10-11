;;; Hetzner Cloud firewalls.

(define-module (chaudron hetzner firewall)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:export (allow-in
            hetzner-firewall
            apply-firewall!
            remove-firewall!))

(define* (allow-in protocol #:optional port
                   #:key (from '("0.0.0.0/0" "::/0")))
  "Return a rule allowing incoming PROTOCOL traffic ('tcp, 'udp, 'icmp...)
to PORT, a number or a range such as \"8000-8100\", from the FROM networks."
  `((protocol . ,(symbol->string protocol))
    (port . ,(and port (if (number? port) (number->string port) port)))
    (from . ,from)))

(define (rule->json rule)
  `(("direction" . "in")
    ("protocol" . ,(assq-ref rule 'protocol))
    ,@(if (assq-ref rule 'port)
          `(("port" . ,(assq-ref rule 'port)))
          '())
    ("source_ips" . ,(list->vector (assq-ref rule 'from)))))

(define (rules->json props)
  (list->vector (map rule->json (assq-ref props 'rules))))

(define (create-firewall _ props)
  (let* ((response (hetzner-request 'POST "/firewalls"
                                    `(("name" . ,(assq-ref props 'name))
                                      ("rules" . ,(rules->json props))
                                      ("labels" . ,(labels->json props)))))
         (outputs `((id . ,(json-ref response "firewall" "id")))))
    (created! outputs props)
    (wait-for-actions response)
    outputs))

;; Rules are not checked for drift: they come back from the API in a
;; normalized form that would not compare equal to ours.
(define (read-firewall outputs)
  (and=> (json-ref (hetzner-get (resource-path "firewalls" (assq-ref outputs 'id)))
                   "firewall")
         (lambda (firewall)
           (cons (observe-metadata firewall) outputs))))

(define (update-firewall outputs old new)
  (let ((id (assq-ref outputs 'id)))
    (update-metadata! "firewalls" id old new)
    (unless (equal? (assq-ref old 'rules) (assq-ref new 'rules))
      (resource-action "firewalls" id "set_rules"
                       `(("rules" . ,(rules->json new))))))
  outputs)

(define (delete-firewall outputs)
  (hetzner-delete (resource-path "firewalls" (assq-ref outputs 'id))))

(define firewall-provider
  (register-provider!
   (make-provider 'hetzner-firewall
                  #:create create-firewall
                  #:read read-firewall
                  #:update update-firewall
                  #:delete delete-firewall)))

(define* (hetzner-firewall resource-name
                           #:key (rules '()) (labels '()) name)
  "Declare a firewall allowing incoming traffic matching RULES, built with
`allow-in'.  Outgoing traffic is always allowed."
  (ensure-resource firewall-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (rules . ,rules)
                     (labels . ,(sorted-labels labels)))))

;;; Applying firewalls to servers.

(define (server-target server)
  (vector `(("type" . "server") ("server" . (("id" . ,server))))))

(define (apply-firewall! firewall server)
  (resource-action "firewalls" firewall "apply_to_resources"
                   `(("apply_to" . ,(server-target server)))))

(define (remove-firewall! firewall server)
  (resource-action "firewalls" firewall "remove_from_resources"
                   `(("remove_from" . ,(server-target server)))))
