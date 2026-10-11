(use-modules (gnu)
             (gnu machine hetzner)
             (guix gexp))
(use-service-modules certbot web)

(define %base
  (make-hetzner-os "cx33"))

(define %domain
  "nginx.enzolegrand.dev")

;; Make nginx pick up the certificate once certbot has obtained it.
(define %nginx-deploy-hook
  (program-file
   "nginx-deploy-hook"
   #~(let ((pid (call-with-input-file "/var/run/nginx/pid" read)))
       (kill pid SIGHUP))))

(operating-system
  (inherit %base)
  (host-name "forge")
  (timezone "Europe/Paris")
  (packages (append (specifications->packages '("git" "htop" "fastfetch"))
                    %base-packages))
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
                            (locations
                             (list (nginx-location-configuration
                                    (uri "/")
                                    (body
                                     '("default_type text/plain;"
                                       "return 200 \"Hello from chaudron!\\n\";"))))))))))
          ;; Gets and renews the certificate from Let's Encrypt, answering its
          ;; challenges on port 80 and redirecting the rest to HTTPS.
          (service certbot-service-type
                   (certbot-configuration
                    (certificates
                     (list (certificate-configuration
                            (domains (list %domain))
                            (deploy-hook %nginx-deploy-hook))))))
          (operating-system-user-services %base))))
