;;; Resources and the providers that manage them.

(define-module (chaudron resource)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-9 gnu)
  #:export (make-provider
            provider?
            provider-kind
            provider-create
            provider-read
            provider-update
            provider-delete
            provider-replace-on
            register-provider!
            lookup-provider

            make-resource
            resource?
            resource-kind
            resource-name
            resource-props
            resource-outputs
            output
            unknown?))

;; A provider knows how to manage one kind of resource:
;;   CREATE  (name props) -> outputs
;;   READ    (outputs) -> (observed-props . outputs), or #f if it is gone;
;;           optional, it lets chaudron notice changes made behind its back
;;   UPDATE  (outputs old-props new-props) -> outputs, or #f to always replace
;;   DELETE  (outputs)
;;   REPLACE-ON  props that cannot change in place.
;; Props and outputs are alists keyed by symbols.
(define-record-type <provider>
  (%make-provider kind create read update delete replace-on)
  provider?
  (kind provider-kind)
  (create provider-create)
  (read provider-read)
  (update provider-update)
  (delete provider-delete)
  (replace-on provider-replace-on))

(define* (make-provider kind #:key create read update delete (replace-on '()))
  (%make-provider kind create read update delete replace-on))

;; Providers are registered by kind, so that resources found in the state
;; can be deleted even when the code no longer declares them.
(define %providers (make-hash-table))

(define (register-provider! provider)
  (hashq-set! %providers (provider-kind provider) provider)
  provider)

(define (lookup-provider kind)
  (hashq-ref %providers kind))

(define-record-type <resource>
  (make-resource kind name props outputs)
  resource?
  (kind resource-kind)
  (name resource-name)
  (props resource-props)
  (outputs resource-outputs))

;; The outputs of a resource that a dry run would create are not known yet.
(define-record-type <unknown>
  (make-unknown resource key)
  unknown?
  (resource unknown-resource)
  (key unknown-key))

(set-record-type-printer! <unknown>
  (lambda (unknown port)
    (let ((resource (unknown-resource unknown)))
      (format port "#<unknown ~a/~a ~a>" (resource-kind resource)
              (resource-name resource) (unknown-key unknown)))))

(define (output resource key)
  "Return the output KEY of RESOURCE, such as its 'id or 'ipv4.  During a
dry run, the outputs of resources that do not exist yet are unknown."
  (match (resource-outputs resource)
    (#f (make-unknown resource key))
    (outputs
     (match (assq key outputs)
       ((_ . value) value)
       (#f (error "no such output" key (resource-name resource)))))))
