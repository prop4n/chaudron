(use-modules (chaudron)
             (chaudron cloudflare)
             (chaudron hetzner)
             (ice-9 match))

;; HCLOUD_TOKEN and CLOUDFLARE_API_TOKEN, unless already set.
(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "prod" #:dry-run? dry-run?
    (define-values (key web ip data)
      (concurrently
       (hetzner-ssh-key "propan" #:public-key-file "~/.ssh/id_ed25519.pub")
       (hetzner-firewall "web"
                         #:rules (list (allow-in 'tcp 22)
                                       (allow-in 'tcp 80)
                                       (allow-in 'tcp 443)
                                       (allow-in 'icmp)))
       (hetzner-primary-ip "forge" #:location "fsn1")
       (hetzner-volume "data" #:size 10 #:location "fsn1")))

    (define forge
      (hetzner-server "forge"
                      #:type "cx23"
                      #:location "fsn1"
                      #:image "ubuntu-24.04"
                      #:ssh-keys (list key)
                      #:firewalls (list web)
                      #:ipv4 ip
                      #:volumes (list data)))

    (define nginx
      (cloudflare-dns-record "nginx"
                             #:zone "enzolegrand.dev"
                             #:content (output forge 'ipv4)))

    (hetzner-guix-system "forge"
                         #:server forge
                         #:os (string-append (dirname (current-filename))
                                             "/forge-os.scm")
                         #:ssh-key key)

    (format #t "ssh root@~a~%" (output forge 'ipv4))
    (format #t "https://~a~%" (output nginx 'name))))

(match (command-line)
  ((_ "destroy") (destroy-stage "prod"))
  ((_ "dry-run") (deploy #t))
  (_ (deploy #f)))
