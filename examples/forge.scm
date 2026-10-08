(use-modules (chaudron)
             (chaudron hetzner))

(with-stage "prod"
  (define key
    (hetzner-ssh-key "propan" #:public-key-file "~/.ssh/id_ed25519.pub"))

  (define ssh-only
    (hetzner-firewall "ssh"
                      #:rules (list (allow-in 'tcp 22)
                                    (allow-in 'icmp))))

  ;; Survive the server being replaced: same address, same data.
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
  (format #t "data: ~a~%" (output data 'linux-device)))
