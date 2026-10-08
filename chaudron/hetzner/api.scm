;;; Minimal client for the Hetzner Cloud API.

(define-module (chaudron hetzner api)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (web client)
  #:use-module (web http)
  #:use-module (web response)
  #:export (hetzner-token
            hetzner-transport
            hetzner-sleep
            hetzner-request
            hetzner-get
            hetzner-delete
            wait-for-action
            wait-for-actions
            json-ref
            json-list

            hetzner-error?
            hetzner-error-status
            hetzner-error-code))

(define %endpoint "https://api.hetzner.cloud/v1")
(define %attempts 3)
(define %action-timeout 600)            ;seconds

;; API token; when unset, $HCLOUD_TOKEN is used.
(define hetzner-token (make-parameter #f))

(define (http-transport method url headers body)
  "Perform an HTTP request; return its status code and body as a string."
  (receive (response bytes)
      (http-request url #:method method #:headers headers
                    #:body (and body (string->utf8 body))
                    #:decode-body? #f)
    (values (response-code response) (and bytes (utf8->string bytes)))))

;; Procedure (method url headers body) -> status, body.  Swapped in tests.
(define hetzner-transport (make-parameter http-transport))

;; Procedure called to wait between retries and polls.  Swapped in tests.
(define hetzner-sleep (make-parameter sleep))

(define (json-ref json . keys)
  "Follow KEYS through nested JSON objects; return #f if one is missing."
  (fold (lambda (key json) (and (pair? json) (assoc-ref json key)))
        json keys))

(define (json-list json . keys)
  "Like `json-ref', but return the JSON array found as a list."
  (match (apply json-ref json keys)
    ((? vector? vector) (vector->list vector))
    (_ '())))

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

(define (request-headers)
  `((authorization
     . ,(parse-header 'authorization (string-append "Bearer " (token))))
    (content-type application/json)))

(define (retryable? status)
  (or (= status 429) (>= status 500)))

(define* (hetzner-request method path #:optional body)
  "Call the Hetzner Cloud API and return the decoded JSON response.
Rate limits and server errors are retried with exponential backoff."
  (let loop ((attempt 1))
    (receive (status text)
        ((hetzner-transport) method (string-append %endpoint path)
         (request-headers) (and body (scm->json-string body)))
      (cond ((< status 300)
             (if (and text (not (string-null? text)))
                 (json-string->scm text)
                 '()))
            ((and (retryable? status) (< attempt %attempts))
             ((hetzner-sleep) (expt 2 attempt))
             (loop (1+ attempt)))
            (else
             (raise-hetzner-error
              status
              (json-ref (and text (false-if-exception (json-string->scm text)))
                        "error")))))))

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

(define (wait-for-action action)
  "Poll ACTION until it completes; raise an error if it fails or takes more
than ten minutes.  Do nothing if ACTION is #f or null."
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
                        'GET (format #f "/actions/~a" (json-ref action "id")))
                       "action")
             (1+ seconds))))))

(define (wait-for-actions response)
  "Wait for every action of RESPONSE, whether it has an \"action\", a list
of \"actions\" or \"next_actions\"."
  (wait-for-action (json-ref response "action"))
  (for-each wait-for-action
            (append (json-list response "actions")
                    (json-list response "next_actions"))))
