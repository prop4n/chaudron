;; HCLOUD_TOKEN=... guile -L . examples/forge.scm          deploy
;; HCLOUD_TOKEN=... guile -L . examples/forge.scm destroy  delete everything

(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(match (command-line)
  ((_ "destroy")
   (destroy-stage "prod"))
  (_
   (with-stage "prod"
     (define key
       (hetzner-ssh-key "propan" #:public-key-file "~/.ssh/id_ed25519.pub"))

     (define ssh-only
       (hetzner-firewall "ssh"
                         #:rules (list (allow-in 'tcp 22)
                                       (allow-in 'icmp))))

     (define ip
       (hetzner-primary-ip "forge" #:location "fsn1"))

     (define data
       (hetzner-volume "data" #:size 10 #:location "fsn1"))

     (define forge
       (hetzner-server "forge"
                       #:type "cx23"
                       #:location "fsn1"
                       #:image "ubuntu-24.04"
                       #:ssh-keys (list key)
                       #:firewalls (list ssh-only)
                       #:ipv4 ip
                       #:volumes (list data)))

     (format #t "ssh root@~a~%" (output forge 'ipv4))
     (format #t "data: ~a~%" (output data 'linux-device)))))
