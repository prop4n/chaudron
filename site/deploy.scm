;;; Builds the website and deploys it to chaudron.dev, as a Cloudflare
;;; Worker serving public/.  From site/:
;;;
;;;   guix time-machine -C channels.lock.scm -- shell -m manifest.scm -- guile deploy.scm
;;;
;;; The Cloudflare token is read from .env.

(use-modules (chaudron)
             (chaudron cloudflare)
             (ice-9 match))

(load-env-file ".env")

(define (deploy)
  (unless (zero? (system* "haunt" "build"))
    (error "could not build the site"))
  (with-stage "prod"
    (let ((site (cloudflare-worker "site"
                                   #:assets "public"
                                   #:domain "chaudron.dev")))
      (format #t "~a~%" (output site 'url)))))

(match (command-line)
  ((_ "destroy") (destroy-stage "prod"))
  (_ (deploy)))
