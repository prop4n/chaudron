;; The system of guix-system.scm: nginx serving public/, over HTTPS with a
;; certificate from Let's Encrypt.

(use-modules (gnu)
             (gnu machine hetzner)
             (guix gexp))
(use-service-modules certbot web)

(define %base
  (make-hetzner-os "cx23"))

(define %domain
  "www.example.com")

;; Make nginx pick up the certificate once certbot has obtained it.
(define %nginx-reload
  (program-file
   "nginx-reload"
   #~(let ((pid (call-with-input-file "/var/run/nginx/pid" read)))
       (kill pid SIGHUP))))

(operating-system
  (inherit %base)
  (host-name "web")
  (services
   (cons* (service nginx-service-type
                   (nginx-configuration
                    (server-blocks
                     (list (nginx-server-configuration
                            (server-name (list %domain))
                            (listen '("443 ssl" "[::]:443 ssl"))
                            (ssl-certificate
                             (string-append "/etc/certs/" %domain
                                            "/fullchain.pem"))
                            (ssl-certificate-key
                             (string-append "/etc/certs/" %domain
                                            "/privkey.pem"))
                            (root (local-file "../public" "site"
                                              #:recursive? #t)))))))
          ;; Answers Let's Encrypt on port 80, and sends the rest to HTTPS.
          (service certbot-service-type
                   (certbot-configuration
                    (certificates
                     (list (certificate-configuration
                            (domains (list %domain))
                            (deploy-hook %nginx-reload))))))
          (operating-system-user-services %base))))
