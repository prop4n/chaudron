;; Port forwards and a fixed address on an Orange Livebox, from the local
;; network.
;;
;;   guile -L lib examples/livebox.scm dry-run    see what would change
;;   guile -L lib examples/livebox.scm            apply
;;   guile -L lib examples/livebox.scm destroy    remove them
;;
;; Needs LIVEBOX_PASSWORD, and LIVEBOX_USERNAME if it is not admin, in the
;; environment or in .env.  The Livebox provider is experimental.

(use-modules (chaudron)
             (chaudron livebox)
             (ice-9 match))

(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "home" #:dry-run? dry-run?
    (livebox-dhcp-lease "server" #:mac "aa:bb:cc:00:11:22" #:ip "192.168.1.200")
    (livebox-port-forward "https" #:port 443 #:to "192.168.1.200")
    (livebox-port-forward "wireguard" #:port 51820 #:to "192.168.1.200"
                          #:protocol 'udp)))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "home"))
  (_ (deploy #f)))
