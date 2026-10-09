;;; Resources of Orange's Livebox: port forwards and static DHCP leases.
;;; Experimental: its API is undocumented, and was only tried on a Livebox
;;; Fibre.

(define-module (chaudron livebox)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron livebox api)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:re-export (livebox-host
               livebox-username
               livebox-password
               livebox-error?
               livebox-error-code)
  #:export (livebox-port-forward
            livebox-dhcp-lease))

;;; Port forwards.

(define %protocols
  '((tcp . "6") (udp . "17") (both . "6,17")))

(define (port-forwards)
  "Return the port forwards of the web interface, by id."
  (match (json-ref (livebox-call "Firewall" "getPortForwarding"
                                 '(("origin" . "webui")))
                   "status")
    ((? pair? rules) rules)
    (_ '())))

(define (set-port-forward props)
  (json-ref (livebox-call "Firewall" "setPortForwarding"
                          `(("id" . ,(assq-ref props 'id))
                            ("origin" . "webui")
                            ("description" . ,(assq-ref props 'id))
                            ("sourceInterface" . "data")
                            ("sourcePrefix" . "")
                            ("protocol" . ,(assq-ref props 'protocol))
                            ("externalPort" . ,(assq-ref props 'port))
                            ("internalPort" . ,(assq-ref props 'internal-port))
                            ("destinationIPAddress" . ,(assq-ref props 'to))
                            ("enable" . ,(assq-ref props 'enabled?))
                            ("persistent" . #t)))
            "status"))

(define (create-port-forward _ props)
  `((id . ,(set-port-forward props))))

(define (read-port-forward outputs)
  (match (assoc (assq-ref outputs 'id) (port-forwards))
    (#f #f)
    ((_ . rule)
     (cons `((port . ,(json-ref rule "ExternalPort"))
             (internal-port . ,(json-ref rule "InternalPort"))
             (to . ,(json-ref rule "DestinationIPAddress"))
             (protocol . ,(json-ref rule "Protocol"))
             (enabled? . ,(eq? #t (json-ref rule "Enable"))))
           outputs))))

(define (update-port-forward outputs old new)
  ;; Setting a rule again, under the same id, updates it.
  (set-port-forward new)
  outputs)

(define (delete-port-forward outputs)
  (when (assoc (assq-ref outputs 'id) (port-forwards))
    (livebox-call "Firewall" "deletePortForwarding"
                  `(("id" . ,(assq-ref outputs 'id))
                    ("origin" . "webui")))))

(define port-forward-provider
  (register-provider!
   (make-provider 'livebox-port-forward
                  #:create create-port-forward
                  #:read read-port-forward
                  #:update update-port-forward
                  #:delete delete-port-forward
                  #:replace-on '(id))))

(define (port->string port)
  (if (number? port) (number->string port) port))

(define* (livebox-port-forward resource-name
                               #:key port to (protocol 'tcp)
                               (internal-port port) (enabled? #t))
  "Forward PORT, a number or a range such as \"8000-8100\", of the public
address to INTERNAL-PORT of TO, an address on the LAN.  PROTOCOL is 'tcp,
'udp or 'both.  RESOURCE-NAME, made of letters, digits, - and _, names the
rule in the Livebox: declaring the name of an existing rule takes it over."
  (unless (and port to)
    (error "livebox-port-forward: #:port and #:to are required" resource-name))
  (unless (string-every (lambda (c) (or (char-alphabetic? c) (char-numeric? c)
                                        (memv c '(#\- #\_))))
                        resource-name)
    (error "livebox-port-forward: invalid name" resource-name))
  (ensure-resource port-forward-provider resource-name
                   `((id . ,resource-name)
                     (port . ,(port->string port))
                     (internal-port . ,(port->string internal-port))
                     (to . ,to)
                     (protocol . ,(or (assq-ref %protocols protocol)
                                      (error "unknown protocol" protocol)))
                     (enabled? . ,(and enabled? #t)))))

;;; Static DHCP leases.

(define %pool "DHCPv4.Server.Pool.default")

(define (static-leases)
  (match (json-ref (livebox-call %pool "getStaticLeases") "status")
    ((? vector? leases) (vector->list leases))
    (_ '())))

(define (lease-of mac)
  (find (lambda (lease)
          (string-ci=? mac (or (json-ref lease "MACAddress") "")))
        (static-leases)))

(define (create-lease _ props)
  (livebox-call %pool "addStaticLease"
                `(("MACAddress" . ,(assq-ref props 'mac))
                  ("IPAddress" . ,(assq-ref props 'ip))))
  `((mac . ,(assq-ref props 'mac))))

(define (read-lease outputs)
  (and=> (lease-of (assq-ref outputs 'mac))
         (lambda (lease)
           (cons `((ip . ,(json-ref lease "IPAddress"))) outputs))))

(define (delete-lease outputs)
  (when (lease-of (assq-ref outputs 'mac))
    (livebox-call %pool "deleteStaticLease"
                  `(("MACAddress" . ,(assq-ref outputs 'mac))))))

(define dhcp-lease-provider
  (register-provider!
   ;; Without #:update, any change deletes the lease and adds it again.
   (make-provider 'livebox-dhcp-lease
                  #:create create-lease
                  #:read read-lease
                  #:delete delete-lease)))

(define* (livebox-dhcp-lease resource-name #:key mac ip)
  "Always give address IP to the device whose MAC address is MAC."
  (unless (and mac ip)
    (error "livebox-dhcp-lease: #:mac and #:ip are required" resource-name))
  (ensure-resource dhcp-lease-provider resource-name
                   `((mac . ,(string-downcase mac))
                     (ip . ,ip))))
