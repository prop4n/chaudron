(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(define (deploy dry-run?)
  (with-stage "prod" #:dry-run? dry-run?
    (define-values (key ssh-only ip data)
      (concurrently
       (hetzner-ssh-key "propan" #:public-key-file "~/.ssh/id_ed25519.pub")
       (hetzner-firewall "ssh"
                         #:rules (list (allow-in 'tcp 22)
                                       (allow-in 'icmp)))
       (hetzner-primary-ip "forge" #:location "fsn1")
       (hetzner-volume "data" #:size 10 #:location "fsn1")))

    (define forge
      (hetzner-server "forge"
                      #:type "cx23"
                      #:location "fsn1"
                      #:image "ubuntu-24.04"
                      #:ssh-keys (list key)
                      #:firewalls (list ssh-only)
                      #:ipv4 ip
                      #:volumes (list data)))

    (hetzner-guix-system "forge"
                         #:server forge
                         #:os (string-append (dirname (current-filename))
                                             "/forge-os.scm")
                         #:ssh-key key)

    (format #t "ssh root@~a~%" (output forge 'ipv4))))

(match (command-line)
  ((_ "destroy") (destroy-stage "prod"))
  ((_ "dry-run") (deploy #t))
  (_ (deploy #f)))
