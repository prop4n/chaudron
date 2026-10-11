;; A static site on Guix System, as in the "A static site on Guix System"
;; recipe of the documentation.  From lib/:
;;
;;   guile -L . examples/static-site/deploy.scm dry-run
;;   guile -L . examples/static-site/deploy.scm
;;   guile -L . examples/static-site/deploy.scm destroy

(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare)
             (ice-9 match))

;; HCLOUD_TOKEN and CLOUDFLARE_API_TOKEN, unless already set.
(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "site" #:dry-run? dry-run?
    (define key
      (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))

    (define web
      (hetzner-firewall "web" #:rules (list (allow-in 'tcp 22)
                                            (allow-in 'tcp 80)
                                            (allow-in 'tcp 443))))

    (define server
      (hetzner-server "site"
                      #:type "cx23"
                      #:location "fsn1"
                      #:ssh-keys (list key)
                      #:firewalls (list web)))

    (hetzner-guix-system "site"
                         #:server server
                         #:os "examples/static-site/site-os.scm"
                         #:ssh-key key)

    (define record
      (cloudflare-dns-record "chaudron-demo"
                             #:zone "enzolegrand.dev"
                             #:content (output server 'ipv4)))

    (format #t "https://~a/~%ssh root@~a~%"
            (output record 'name) (output server 'ipv4))))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "site"))
  (_ (deploy #f)))
