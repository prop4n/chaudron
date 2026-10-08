;; A server reachable over SSH only.
;;
;;   HCLOUD_TOKEN=... guile -L . examples/forge.scm
;;   HCLOUD_TOKEN=... guile -L . examples/forge.scm destroy

(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(match (command-line)
  ((_ "destroy")
   (destroy-stage "prod"))
  (_
   (with-stage "prod"
     (define key
       (hetzner-ssh-key "moi" #:public-key-file "~/.ssh/id_ed25519.pub"))

     (define ssh-only
       (hetzner-firewall "ssh-only"
                         #:rules (list (allow-in 'tcp 22)
                                       (allow-in 'icmp))))

     (define forge
       (hetzner-server "forge"
                       #:type "cx23"
                       #:location "fsn1"
                       #:ssh-keys (list key)
                       #:firewalls (list ssh-only)))

     (format #t "ssh root@~a~%" (output forge 'ipv4)))))
