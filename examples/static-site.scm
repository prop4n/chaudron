;; A static site on Cloudflare, at a domain of yours.
;; guile -L lib examples/static-site.scm [destroy]

(use-modules (chaudron)
             (chaudron cloudflare)
             (ice-9 match))

(load-env-file ".env")

(define %domain "www.example.com")
(define %directory "public")

(define (deploy)
  (with-stage "site"
    (let ((site (cloudflare-worker "site"
                                   #:assets %directory
                                   #:domain %domain)))
      (format #t "~a~%" (output site 'url)))))

(match (command-line)
  ((_ "destroy") (destroy-stage "site"))
  (_ (deploy)))
