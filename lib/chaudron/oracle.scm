;;; Oracle Cloud resources.

(define-module (chaudron oracle)
  #:use-module (chaudron oracle api)
  #:use-module (chaudron oracle bucket)
  #:use-module (chaudron oracle guix-system)
  #:use-module (chaudron oracle image)
  #:use-module (chaudron oracle instance)
  #:use-module (chaudron oracle network)
  #:use-module (chaudron oracle object)
  #:re-export (oracle-bucket
               oracle-object
               oracle-image
               oracle-network
               oracle-instance
               oracle-guix-system
               oracle-compartment
               oracle-error?
               oracle-error-status
               oracle-error-code))
