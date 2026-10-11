;; A static site served by Cloudflare, with HTTPS, and no server: the files
;; of a directory, at a domain of yours.
;;
;;   guile -L lib examples/static-site.scm           deploy, or update
;;   guile -L lib examples/static-site.scm destroy   delete it
;;
;; Needs CLOUDFLARE_API_TOKEN, allowed to edit Workers, and DNS in the zone
;; of the domain.

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
