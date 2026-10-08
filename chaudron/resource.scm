;;; Resources and the providers that manage them.

(define-module (chaudron resource)
  #:use-module (srfi srfi-9)
  #:export (make-provider
            provider?
            provider-kind
            provider-create
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
            output))

;; A provider knows how to manage one kind of resource:
;;   CREATE  (name props) -> outputs
;;   UPDATE  (outputs old-props new-props) -> outputs, or #f to always replace
;;   DELETE  (outputs)
;;   REPLACE-ON  props that cannot change in place.
;; Props and outputs are alists keyed by symbols.
(define-record-type <provider>
  (%make-provider kind create update delete replace-on)
  provider?
  (kind provider-kind)
  (create provider-create)
  (update provider-update)
  (delete provider-delete)
  (replace-on provider-replace-on))

(define* (make-provider kind #:key create update delete (replace-on '()))
  (%make-provider kind create update delete replace-on))

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

(define (output resource key)
  "Return the output KEY of RESOURCE, such as its 'id or 'ipv4."
  (let ((pair (assq key (resource-outputs resource))))
    (unless pair
      (error "no such output" key (resource-name resource)))
    (cdr pair)))
