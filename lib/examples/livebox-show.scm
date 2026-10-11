;; Show what the Livebox knows: public address, port forwards, DHCP leases.
;; Read-only.
;;
;;   guile -L . examples/livebox-show.scm

(use-modules (chaudron)
             (chaudron livebox api)
             (ice-9 match))

;; LIVEBOX_USERNAME and LIVEBOX_PASSWORD.
(load-env-file ".env")

(define (status service method . parameters)
  (json-ref (livebox-call service method (match parameters
                                           (() '())
                                           ((alist) alist)))
            "status"))

(define wan
  (json-ref (livebox-call "NMC" "getWANStatus") "data"))

(format #t "Public address: ~a~%IPv6 prefix:    ~a~%~%"
        (json-ref wan "IPAddress") (json-ref wan "IPv6DelegatedPrefix"))

(format #t "Port forwards:~%")
(for-each (match-lambda
            ((id . rule)
             ;; The name to give `livebox-port-forward' to take it over.
             (format #t "  ~a~22t~a  ~a/~a → ~a:~a~%"
                     (if (string-prefix? "webui_" id) (string-drop id 6) id)
                     (if (eq? #t (json-ref rule "Enable")) "on " "off")
                     (json-ref rule "ExternalPort")
                     (match (json-ref rule "Protocol")
                       ("6" "tcp") ("17" "udp") ("6,17" "tcp+udp")
                       (other other))
                     (json-ref rule "DestinationIPAddress")
                     (json-ref rule "InternalPort"))))
          (or (status "Firewall" "getPortForwarding" '(("origin" . "webui")))
              '()))

(format #t "~%Static DHCP leases:~%")
(match (vector->list (status "DHCPv4.Server.Pool.default" "getStaticLeases"))
  (() (format #t "  none~%"))
  (leases
   (for-each (lambda (lease)
               (format #t "  ~a → ~a~%" (json-ref lease "MACAddress")
                       (json-ref lease "IPAddress")))
             leases)))
