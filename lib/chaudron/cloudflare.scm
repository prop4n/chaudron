;;; Cloudflare resources.

(define-module (chaudron cloudflare)
  #:use-module (chaudron cloudflare api)
  #:use-module (chaudron cloudflare dns)
  #:re-export (cloudflare-dns-record
               cloudflare-token
               cloudflare-error?
               cloudflare-error-status
               cloudflare-error-code)
  #:export (with-cloudflare))

(define-syntax-rule (with-cloudflare token body ...)
  "Evaluate BODY using TOKEN to authenticate against Cloudflare."
  (parameterize ((cloudflare-token token))
    body ...))
