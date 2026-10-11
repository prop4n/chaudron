;; What goes in the Docker image of chaudron: Guile, chaudron, and what
;; HTTPS needs, the certificates and /etc/services.
;;
;;   guix pack -f docker -m .guix/image.scm --entry-point=bin/guile \
;;     -S /bin=bin -S /etc/services=etc/services \
;;     -S /etc/ssl/certs=etc/ssl/certs --image-tag=chaudron

(add-to-load-path (string-append (dirname (current-filename)) "/modules"))

(use-modules (chaudron-package)
             (gnu packages admin)
             (gnu packages nss)
             (gnu packages guile)
             (guix profiles))

(packages->manifest (list guile-3.0 chaudron net-base nss-certs))
