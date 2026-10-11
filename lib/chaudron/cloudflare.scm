;;; Cloudflare resources.

(define-module (chaudron cloudflare)
  #:use-module (chaudron cloudflare api)
  #:use-module (chaudron cloudflare d1)
  #:use-module (chaudron cloudflare dns)
  #:use-module (chaudron cloudflare kv)
  #:use-module (chaudron cloudflare worker)
  #:re-export (cloudflare-dns-record
               cloudflare-kv-namespace
               cloudflare-d1-database
               cloudflare-worker
               kv-binding
               d1-binding
               cloudflare-token
               cloudflare-account-id
               cloudflare-error?
               cloudflare-error-status
               cloudflare-error-code)
  #:export (with-cloudflare))

(define-syntax-rule (with-cloudflare token body ...)
  "Evaluate BODY using TOKEN to authenticate against Cloudflare."
  (parameterize ((cloudflare-token token))
    body ...))
