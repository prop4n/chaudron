;;; Deploys the website to chaudron.dev, as a Cloudflare Worker serving
;;; public/.  From site/:
;;;
;;;   guix shell -m manifest.scm -m ../lib/manifest.scm -- guile -L ../lib deploy.scm
;;;
;;; It builds the site first.  The Cloudflare token is read from ../lib/.env.

(use-modules (chaudron)
             (chaudron cloudflare)
             (ice-9 match))

(load-env-file "../lib/.env")

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
