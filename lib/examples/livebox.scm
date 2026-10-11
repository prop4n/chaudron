;; Declare port forwards and DHCP leases on the Livebox.  These two are
;; harmless: a disabled forward to an empty address, and a lease for a
;; made-up MAC.
;;
;;   guile -L . examples/livebox.scm dry-run   show what would change
;;   guile -L . examples/livebox.scm           apply
;;   guile -L . examples/livebox.scm destroy   remove them from the Livebox

(use-modules (chaudron)
             (chaudron livebox)
             (ice-9 match))

;; LIVEBOX_USERNAME and LIVEBOX_PASSWORD.
(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "livebox-demo" #:dry-run? dry-run?
    (livebox-port-forward "chaudron-demo"
                          #:port 65432
                          #:to "192.168.1.250"
                          #:protocol 'both
                          #:enabled? #f)

    (livebox-dhcp-lease "chaudron-demo"
                        #:mac "02:00:00:c4:a0:01"
                        #:ip "192.168.1.250")))

(match (command-line)
  ((_ "destroy") (destroy-stage "livebox-demo"))
  ((_ "dry-run") (deploy #t))
  (_ (deploy #f)))
