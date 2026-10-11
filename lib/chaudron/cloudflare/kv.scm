;;; Cloudflare Workers KV namespaces.

(define-module (chaudron cloudflare kv)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron cloudflare api)
  #:use-module (ice-9 match)
  #:export (cloudflare-kv-namespace))

(define (namespace-path outputs)
  (string-append "/accounts/" (assq-ref outputs 'account-id)
                 "/storage/kv/namespaces/" (assq-ref outputs 'id)))

(define (create-namespace _ props)
  (let* ((account (account-id))
         (namespace (cloudflare-request
                     'POST (string-append "/accounts/" account
                                          "/storage/kv/namespaces")
                     `(("title" . ,(assq-ref props 'title))))))
    `((id . ,(json-ref namespace "id"))
      (account-id . ,account))))

(define (read-namespace outputs)
  (and=> (cloudflare-get (namespace-path outputs))
         (lambda (namespace)
           (cons `((title . ,(json-ref namespace "title"))) outputs))))

(define (update-namespace outputs old new)
  (cloudflare-request 'PUT (namespace-path outputs)
                      `(("title" . ,(assq-ref new 'title))))
  outputs)

(define (delete-namespace outputs)
  (cloudflare-delete (namespace-path outputs)))

(define namespace-provider
  (register-provider!
   (make-provider 'cloudflare-kv-namespace
                  #:create create-namespace
                  #:read read-namespace
                  #:update update-namespace
                  #:delete delete-namespace)))

(define* (cloudflare-kv-namespace resource-name #:key title)
  "Declare a KV namespace, a key-value store for Workers, given to them
with `kv-binding'.  It is titled after RESOURCE-NAME and the stage, or
TITLE."
  (ensure-resource namespace-provider resource-name
                   `((title . ,(or title
                                   (match (current-stage)
                                     (#f resource-name)
                                     (stage (string-append
                                             resource-name "-"
                                             (stage-name stage)))))))))
