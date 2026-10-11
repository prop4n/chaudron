;; A Hetzner server running Guix System, with nginx serving a directory over
;; HTTPS, and its DNS record at Cloudflare.  Its system is in
;; guix-system-os.scm: change the domain there too.
;;
;;   guile -L lib examples/guix-system.scm           deploy, or update
;;   guile -L lib examples/guix-system.scm destroy   delete everything
;;
;; Needs HCLOUD_TOKEN and CLOUDFLARE_API_TOKEN, in the environment or in
;; .env, and guix, ssh and a Guix signing key on this machine.  The first
;; run erases the server's disk to install Guix System: about eight minutes.

(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare)
             (ice-9 match))

(load-env-file ".env")

(define %zone "example.com")
(define %name "www")

(define (deploy)
  (with-stage "guix"
    (define key
      (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))

    (define web
      (hetzner-firewall "web" #:rules (list (allow-in 'tcp 22)
                                            (allow-in 'tcp 80)
                                            (allow-in 'tcp 443))))

    (define server
      (hetzner-server "web"
                      #:type "cx23"
                      #:location "fsn1"
                      #:ssh-keys (list key)
                      #:firewalls (list web)))

    ;; Before the system: Let's Encrypt checks the domain while deploying.
    (define record
      (cloudflare-dns-record %name
                             #:zone %zone
                             #:content (output server 'ipv4)))

    (hetzner-guix-system "web"
                         #:server server
                         #:os "examples/guix-system-os.scm"
                         #:ssh-key key)

    (format #t "https://~a/~%" (output record 'name))))

(match (command-line)
  ((_ "destroy") (destroy-stage "guix"))
  (_ (deploy)))
