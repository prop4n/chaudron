;;; Minimal client for the Cloudflare API.

(define-module (chaudron cloudflare api)
  #:use-module (chaudron http)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:re-export (json-ref
               json-list)
  #:export (cloudflare-token
            cloudflare-transport
            cloudflare-sleep
            cloudflare-request
            cloudflare-get
            cloudflare-delete
            zone-id

            cloudflare-error?
            cloudflare-error-status
            cloudflare-error-code))

(define %endpoint "https://api.cloudflare.com/client/v4")

;; API token; when unset, $CLOUDFLARE_API_TOKEN is used.
(define cloudflare-token (make-parameter #f))

;; Procedure (method url headers body) -> status, body.  Swapped in tests.
(define cloudflare-transport (make-parameter http-transport))

;; Procedure called to wait between retries.  Swapped in tests.
(define cloudflare-sleep (make-parameter sleep))

;;; Errors.

(define &cloudflare-error
  (make-exception-type '&cloudflare-error &error '(status code)))

(define make-cloudflare-error (record-constructor &cloudflare-error))
(define cloudflare-error? (exception-predicate &cloudflare-error))
(define cloudflare-error-status
  (exception-accessor &cloudflare-error
                      (record-accessor &cloudflare-error 'status)))
(define cloudflare-error-code
  (exception-accessor &cloudflare-error
                      (record-accessor &cloudflare-error 'code)))

(define (raise-cloudflare-error status errors)
  "Raise an exception for the first of ERRORS, those of an API response."
  (let ((error (match errors ((error . _) error) (() #f))))
    (raise-exception
     (make-exception (make-cloudflare-error status (json-ref error "code"))
                     (make-exception-with-message
                      (or (json-ref error "message")
                          (format #f "Cloudflare API error (HTTP ~a)"
                                  status)))))))

;;; Requests.

(define (token)
  (or (cloudflare-token)
      (getenv "CLOUDFLARE_API_TOKEN")
      (error "no Cloudflare token: set CLOUDFLARE_API_TOKEN or use \
with-cloudflare")))

(define* (cloudflare-request method path #:optional body)
  "Call the Cloudflare API and return the \"result\" of its response.  Rate
limits and server errors are retried with exponential backoff."
  (receive (status json)
      (json-request (cloudflare-transport) (cloudflare-sleep)
                    method (string-append %endpoint path)
                    (bearer-headers (token)) body)
    (if (and (< status 300) (eq? #t (json-ref json "success")))
        (json-ref json "result")
        (raise-cloudflare-error status (json-list json "errors")))))

(define (unless-gone thunk)
  "Call THUNK; return #f instead if what it asks for does not exist."
  (guard (e ((and (cloudflare-error? e) (eqv? 404 (cloudflare-error-status e)))
             #f))
    (thunk)))

(define (cloudflare-get path)
  "GET PATH and return its result, or #f if it does not exist."
  (unless-gone (lambda () (cloudflare-request 'GET path))))

(define (cloudflare-delete path)
  "DELETE PATH and return its result, or #f if it was already gone."
  (unless-gone (lambda () (cloudflare-request 'DELETE path))))

(define (zone-id zone)
  "Return the ID of ZONE, a domain name such as \"example.com\"."
  (match (vector->list (or (cloudflare-request
                            'GET (string-append "/zones?name=" zone))
                           #()))
    ((found . _) (json-ref found "id"))
    (() (error "no such Cloudflare zone" zone))))
