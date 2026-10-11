;;; Minimal client for the Cloudflare API.

(define-module (chaudron cloudflare api)
  #:use-module (chaudron http)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (json)
  #:use-module (web http)
  #:re-export (json-ref
               json-list)
  #:export (cloudflare-token
            cloudflare-transport
            cloudflare-sleep
            cloudflare-request
            cloudflare-get
            cloudflare-delete
            cloudflare-upload
            zone-id
            cloudflare-account-id
            account-id

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
  "Call the Cloudflare API and return the \"result\" of its response, or #f
if it has no body.  Rate limits and server errors are retried with
exponential backoff."
  (receive (status json)
      (json-request (cloudflare-transport) (cloudflare-sleep)
                    method (string-append %endpoint path)
                    (bearer-headers (token)) body)
    (cond ((and (< status 300) (not json))  ;as when deleting Worker domains
           #f)
          ((and (< status 300) (eq? #t (json-ref json "success")))
           (json-ref json "result"))
          (else
           (raise-cloudflare-error status (json-list json "errors"))))))

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

(define %boundary "chaudron-form-boundary-7d2f9c")

(define (multipart-form parts)
  "Encode PARTS, a list of (name filename content-type text), as the body of
a multipart/form-data request.  FILENAME may be #f."
  (string-append
   (string-concatenate
    (map (match-lambda
           ((name filename type text)
            (string-append "--" %boundary "\r\n"
                           "Content-Disposition: form-data; name=\"" name "\""
                           (if filename
                               (string-append "; filename=\"" filename "\"")
                               "")
                           "\r\nContent-Type: " type "\r\n\r\n"
                           text "\r\n")))
         parts))
   "--" %boundary "--\r\n"))

(define* (cloudflare-upload method path parts #:key (bearer (token)))
  "Send PARTS, as for `multipart-form', to PATH, authenticated with BEARER,
and return the \"result\" of the response."
  (receive (status text)
      ((cloudflare-transport)
       method (string-append %endpoint path)
       `((authorization . ,(parse-header 'authorization
                                         (string-append "Bearer " bearer)))
         (content-type multipart/form-data (boundary . ,%boundary)))
       (multipart-form parts))
    (let ((json (and text (false-if-exception (json-string->scm text)))))
      (if (and (< status 300) (eq? #t (json-ref json "success")))
          (json-ref json "result")
          (raise-cloudflare-error status (json-list json "errors"))))))

;; Account ID; when unset, $CLOUDFLARE_ACCOUNT_ID, or else the only account
;; the token can reach.
(define cloudflare-account-id (make-parameter #f))

(define (account-id)
  (or (cloudflare-account-id)
      (getenv "CLOUDFLARE_ACCOUNT_ID")
      (match (vector->list (cloudflare-request 'GET "/accounts"))
        ((account) (json-ref account "id"))
        (() (error "the Cloudflare token reaches no account"))
        (_ (error "the Cloudflare token reaches several accounts: set \
CLOUDFLARE_ACCOUNT_ID")))))

(define (zone-id zone)
  "Return the ID of ZONE, a domain name such as \"example.com\"."
  (match (vector->list (or (cloudflare-request
                            'GET (string-append "/zones?name=" zone))
                           #()))
    ((found . _) (json-ref found "id"))
    (() (error "no such Cloudflare zone" zone))))
