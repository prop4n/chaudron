;;; HTTP and JSON plumbing shared by the providers' API clients.

(define-module (chaudron http)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (web client)
  #:use-module (web http)
  #:use-module (web response)
  #:export (http-transport
            json-request
            bearer-headers
            json-ref
            json-list))

(define %attempts 3)

(define (http-transport method url headers body)
  "Perform an HTTP request; return its status code and body as a string."
  (receive (response bytes)
      (http-request url #:method method #:headers headers
                    #:body (and body (string->utf8 body))
                    #:decode-body? #f)
    (values (response-code response) (and bytes (utf8->string bytes)))))

(define (bearer-headers token)
  "Return the headers of a JSON request authenticated with TOKEN."
  `((authorization . ,(parse-header 'authorization
                                    (string-append "Bearer " token)))
    (content-type application/json)))

(define (retryable? status)
  (or (= status 429) (>= status 500)))

(define* (json-request transport sleep method url headers #:optional body)
  "Send BODY, encoded as JSON, to URL using TRANSPORT, a procedure like
`http-transport'.  Retry rate limits and server errors, calling SLEEP with
the number of seconds to wait.  Return the status of the response and its
decoded JSON body, or #f if it has none."
  (let loop ((attempt 1))
    (receive (status text)
        (transport method url headers (and body (scm->json-string body)))
      (if (and (retryable? status) (< attempt %attempts))
          (begin
            (sleep (expt 2 attempt))
            (loop (1+ attempt)))
          (values status
                  (and text (not (string-null? text))
                       (false-if-exception (json-string->scm text))))))))

(define (json-ref json . keys)
  "Follow KEYS through nested JSON objects; return #f if one is missing."
  (fold (lambda (key json) (and (pair? json) (assoc-ref json key)))
        json keys))

(define (json-list json . keys)
  "Like `json-ref', but return the JSON array found as a list."
  (match (apply json-ref json keys)
    ((? vector? vector) (vector->list vector))
    (_ '())))
