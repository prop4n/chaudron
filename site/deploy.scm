(use-modules (chaudron)
             (chaudron cloudflare)
             (ice-9 match))

(load-env-file ".env")

(define (deploy)
  (unless (zero? (system* "haunt" "build"))
    (error "impossible de construire le site"))
  (with-stage "prod"
    (let ((site (cloudflare-worker "site-chaudron"
                                   #:assets "public"
                                   #:domain "chaudron.dev")))
      (format #t "~a~%" (output site 'url)))))

(match (command-line)
  ((_ "destroy") (destroy-stage "prod"))
  (_ (deploy)))
