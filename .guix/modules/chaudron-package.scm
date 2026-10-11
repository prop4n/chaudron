;; The chaudron package, for 'guix build -f guix.scm' and for the channel.

(define-module (chaudron-package)
  #:use-module (guix build-system guile)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages tls)
  #:export (chaudron))

(define %library
  (canonicalize-path (string-append (current-source-directory) "/../../lib")))

(define (library-file? file stat)
  "Only the modules: not the tests, nor anything else lying in lib/."
  (let ((name (string-drop file (string-length %library))))
    (or (string=? name "/chaudron.scm")
        (string=? name "/chaudron")
        (string-prefix? "/chaudron/" name))))

(define chaudron
  (package
    (name "chaudron")
    (version "0.1")
    (source (local-file %library "chaudron-checkout"
                        #:recursive? #t
                        #:select? library-file?))
    (build-system guile-build-system)
    (native-inputs (list guile-3.0))
    (inputs (list guile-3.0))
    (propagated-inputs (list guile-json-4 guile-gnutls guile-gcrypt))
    (home-page "https://chaudron.dev")
    (synopsis "Infrastructure as plain Guile programs")
    (description
     "chaudron is a Guile library to describe infrastructure as a Scheme
program, and to deploy it by running that program.  Each resource call
converges the real resource right away and returns its outputs.  It manages
Hetzner Cloud servers and their companions, Guix System on those servers,
Cloudflare DNS records and Workers, and Orange Livebox routers.")
    (license license:gpl3+)))
