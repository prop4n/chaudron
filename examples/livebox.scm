;; Port forwards and a fixed address on an Orange Livebox.
;; guile -L lib examples/livebox.scm [dry-run | destroy]

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
