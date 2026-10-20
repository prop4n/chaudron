;;; Minimal client for the Hetzner Cloud API.

(define-module (chaudron hetzner api)
  #:use-module (chaudron http)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:re-export (json-ref
               json-list)
  #:export (hetzner-token
            hetzner-transport
            hetzner-sleep
            hetzner-request
            hetzner-get
            hetzner-delete
            wait-for-action
            wait-for-actions

            hetzner-error?
            hetzner-error-status
            hetzner-error-code))

(define %endpoint "https://api.hetzner.cloud/v1")
;; Storage Boxes are in the Hetzner API, which takes the same tokens.
(define %storage-box-endpoint "https://api.hetzner.com/v1")
(define %action-timeout 600)            ;seconds

;; API token; when unset, $HCLOUD_TOKEN is used.
(define hetzner-token (make-parameter #f))

;; Procedure (method url headers body) -> status, body.  Swapped in tests.
(define hetzner-transport (make-parameter http-transport))

;; Procedure called to wait between retries and polls.  Swapped in tests.
(define hetzner-sleep (make-parameter sleep))

;;; Errors.

(define &hetzner-error
  (make-exception-type '&hetzner-error &error '(status code)))

(define make-hetzner-error (record-constructor &hetzner-error))
(define hetzner-error? (exception-predicate &hetzner-error))
(define hetzner-error-status
  (exception-accessor &hetzner-error (record-accessor &hetzner-error 'status)))
(define hetzner-error-code
  (exception-accessor &hetzner-error (record-accessor &hetzner-error 'code)))

(define (raise-hetzner-error status error)
  "Raise an exception for ERROR, the \"error\" object of an API response."
  (raise-exception
   (make-exception (make-hetzner-error status (json-ref error "code"))
                   (make-exception-with-message
                    (or (json-ref error "message")
                        (format #f "Hetzner API error (HTTP ~a)" status))))))

;;; Requests.

(define (token)
  (or (hetzner-token)
      (getenv "HCLOUD_TOKEN")
      (error "no Hetzner token: set HCLOUD_TOKEN or use with-hetzner")))

(define (endpoint path)
  (if (string-prefix? "/storage_boxes" path)
      %storage-box-endpoint
      %endpoint))

(define* (hetzner-request method path #:optional body)
  "Call the Hetzner Cloud API, or the Hetzner API for Storage Boxes, and
return the decoded JSON response.  Rate limits and server errors are retried
with exponential backoff."
  (receive (status json)
      (json-request (hetzner-transport) (hetzner-sleep)
                    method (string-append (endpoint path) path)
                    (bearer-headers (token)) body)
    (if (< status 300)
        (or json '())
        (raise-hetzner-error status (json-ref json "error")))))

(define (unless-gone thunk)
  "Call THUNK; return #f instead if the resource it asks for does not exist."
  (guard (e ((and (hetzner-error? e) (eqv? 404 (hetzner-error-status e)))
             #f))
    (thunk)))

(define (hetzner-get path)
  "GET PATH and return the response, or #f if it does not exist."
  (unless-gone (lambda () (hetzner-request 'GET path))))

(define (hetzner-delete path)
  "DELETE PATH and return the response, or #f if it was already gone."
  (unless-gone (lambda () (hetzner-request 'DELETE path))))

(define* (wait-for-action action #:optional (collection ""))
  "Poll ACTION until it completes; raise an error if it fails or takes more
than ten minutes.  Do nothing if ACTION is #f or null.  COLLECTION, such as
\"/storage_boxes\", is where actions are kept when not at the top."
  (let loop ((action action) (seconds 0))
    (match (json-ref action "status")
      (#f action)
      ("success" action)
      ("error" (raise-hetzner-error #f (json-ref action "error")))
      (_
       (when (>= seconds %action-timeout)
         (error "Hetzner action timed out" (json-ref action "command")))
       ((hetzner-sleep) 1)
       (loop (json-ref (hetzner-request
                        'GET (format #f "~a/actions/~a" collection
                                     (json-ref action "id")))
                       "action")
             (1+ seconds))))))

(define* (wait-for-actions response #:optional (collection ""))
  "Wait for every action of RESPONSE, whether it has an \"action\", a list
of \"actions\" or \"next_actions\"."
  (wait-for-action (json-ref response "action") collection)
  (for-each (lambda (action) (wait-for-action action collection))
            (append (json-list response "actions")
                    (json-list response "next_actions"))))
