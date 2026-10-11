;; The chaudron package, built from this checkout:
;;
;;   guix build -f guix.scm
;;   guix shell -f guix.scm

(add-to-load-path (string-append (dirname (current-filename)) "/.guix/modules"))

(use-modules (chaudron-package))

chaudron
