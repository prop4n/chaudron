;;; Chaudron: infrastructure as plain Guile programs.

(define-module (chaudron)
  #:use-module (chaudron concurrency)
  #:use-module (chaudron env)
  #:use-module (chaudron resource)
  #:use-module (chaudron state)
  #:use-module (chaudron stage)
  #:re-export (with-stage
               call-with-stage
               destroy-stage
               current-stage
               stage-name
               ensure-resource
               created!
               report
               chaudron-error?
               exit-on-failure?
               make-provider
               register-provider!
               resource?
               resource-kind
               resource-name
               resource-props
               resource-outputs
               output
               unknown?
               concurrently
               call-concurrently
               load-env-file
               state-directory))
