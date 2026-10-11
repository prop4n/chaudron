;; The Livebox's port forwards to the homelab, as they are today.
;;
;;   guile -L . examples/livebox-home.scm dry-run   show what would change
;;   guile -L . examples/livebox-home.scm           create them, or take them
;;                                                  over if they exist
;;   guile -L . examples/livebox-home.scm destroy   delete them all: the
;;                                                  homelab is cut off from
;;                                                  the Internet until created
;;                                                  again

(use-modules (chaudron)
             (chaudron livebox)
             (ice-9 match))

;; LIVEBOX_USERNAME and LIVEBOX_PASSWORD.
(load-env-file ".env")

(define %ingress "192.168.1.202")
(define %vpn "192.168.1.203")

(define (deploy dry-run?)
  (with-stage "home" #:dry-run? dry-run?
    ;; The web, relayed by ingress.
    (livebox-port-forward "fronthttp" #:port 80 #:to %ingress)
    (livebox-port-forward "fronthttps" #:port 443 #:to %ingress)
    (livebox-port-forward "frontgit" #:port 2222 #:to %ingress)

    ;; Tailscale: STUN and WireGuard, straight to the VPN.
    (livebox-port-forward "gatewaystun" #:port 3478 #:to %vpn
                          #:protocol 'udp)
    (livebox-port-forward "gatewaywireguard" #:port 41641 #:to %vpn
                          #:protocol 'udp)))

(match (command-line)
  ((_ "destroy") (destroy-stage "home"))
  ((_ "dry-run") (deploy #t))
  (_ (deploy #f)))
