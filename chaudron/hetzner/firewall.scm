;;; Hetzner Cloud firewalls.

(define-module (chaudron hetzner firewall)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:export (allow-in
            hetzner-firewall))

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

(define (firewall-path outputs . rest)
  (apply string-append "/firewalls/" (number->string (assq-ref outputs 'id))
         rest))

(define (create-firewall _ props)
  (let ((response (hetzner-request 'POST "/firewalls"
                                   `(("name" . ,(assq-ref props 'name))
                                     ("rules" . ,(rules->json props))
                                     ("labels" . ,(stage-labels))))))
    (wait-for-actions response)
    `((id . ,(json-ref response "firewall" "id")))))

;; Only the name is checked for drift: rules come back from the API in a
;; normalized form that would not compare equal to ours.
(define (read-firewall outputs)
  (and=> (json-ref (hetzner-get (firewall-path outputs)) "firewall")
         (lambda (firewall)
           (cons `((name . ,(json-ref firewall "name")))
                 outputs))))

(define (update-firewall outputs old new)
  (unless (equal? (assq-ref old 'name) (assq-ref new 'name))
    (hetzner-request 'PUT (firewall-path outputs)
                     `(("name" . ,(assq-ref new 'name)))))
  (unless (equal? (assq-ref old 'rules) (assq-ref new 'rules))
    (wait-for-actions
     (hetzner-request 'POST (firewall-path outputs "/actions/set_rules")
                      `(("rules" . ,(rules->json new))))))
  outputs)

(define (delete-firewall outputs)
  (hetzner-delete (firewall-path outputs)))

(define firewall-provider
  (register-provider!
   (make-provider 'hetzner-firewall
                  #:create create-firewall
                  #:read read-firewall
                  #:update update-firewall
                  #:delete delete-firewall)))

(define* (hetzner-firewall resource-name #:key (rules '()) (name resource-name))
  "Declare a firewall allowing incoming traffic matching RULES, built with
`allow-in'.  Outgoing traffic is always allowed."
  (ensure-resource firewall-provider resource-name
                   `((name . ,name) (rules . ,rules))))
