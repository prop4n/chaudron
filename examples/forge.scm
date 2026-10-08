(use-modules (chaudron)
             (chaudron hetzner))

(with-stage "prod"
  (define key
    (hetzner-ssh-key "propan" #:public-key-file "~/.ssh/id_ed25519.pub"))

  (define ssh-only
    (hetzner-firewall "ssh"
                      #:rules (list (allow-in 'tcp 22)
                                    (allow-in 'icmp))))

  (define forge
    (hetzner-server "forge"
                    #:type "cx23"
                    #:location "fsn1"
                    #:image "ubuntu-24.04"
                    #:ssh-keys (list key)
                    #:firewalls (list ssh-only)))

  (format #t "ssh root@~a~%" (output forge 'ipv4)))
