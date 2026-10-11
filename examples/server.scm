;; A server at Hetzner, reachable over SSH.
;; guile -L lib examples/server.scm [dry-run | destroy]

(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "server" #:dry-run? dry-run?
    (define key
      (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))

    (define ssh
      (hetzner-firewall "ssh" #:rules (list (allow-in 'tcp 22))))

    (define box
      (hetzner-server "box"
                      #:type "cx23"
                      #:location "fsn1"
                      #:ssh-keys (list key)
                      #:firewalls (list ssh)))

    (format #t "ssh root@~a~%" (output box 'ipv4))))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "server"))
  (_ (deploy #f)))
