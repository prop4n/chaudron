;; The system of the static-site example: nginx serving chaudron's website,
;; built in site/public (run 'haunt build' in site/ first), over HTTPS.

(use-modules (gnu)
             (gnu machine hetzner)
             (guix gexp))
(use-service-modules certbot web)

(define %base
  (make-hetzner-os "cx23"))

(define %domain
  "chaudron-demo.enzolegrand.dev")

;; Make nginx pick up the certificate once certbot has obtained it.
(define %nginx-deploy-hook
  (program-file
   "nginx-deploy-hook"
   #~(let ((pid (call-with-input-file "/var/run/nginx/pid" read)))
       (kill pid SIGHUP))))

(operating-system
  (inherit %base)
  (host-name "site")
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
                            ;; The site is copied to the store with the system.
                            (root (local-file "../../../site/public" "site"
                                              #:recursive? #t)))))))
          ;; Gets and renews the certificate from Let's Encrypt, answering its
          ;; challenges on port 80 and redirecting the rest to HTTPS.
          (service certbot-service-type
                   (certbot-configuration
                    (certificates
                     (list (certificate-configuration
                            (domains (list %domain))
                            (deploy-hook %nginx-deploy-hook))))))
          (operating-system-user-services %base))))
