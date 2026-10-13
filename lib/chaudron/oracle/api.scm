;;; Minimal client for the Oracle Cloud Infrastructure API.

(define-module (chaudron oracle api)
  #:use-module (chaudron http)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle signing)
  #:use-module (chaudron command)
  #:use-module (gcrypt base64)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-19)
  #:use-module (web client)
  #:use-module (web http)
  #:use-module (web response)
  #:use-module (web uri)
  #:re-export (json-ref
               json-list)
  #:export (oracle-transport
            oracle-sleep
            oracle-request
            oracle-call
            oracle-get
            oracle-delete
            unless-gone
            oracle-compartment
            oracle-namespace
            physical-name
            wait-for-state

            oracle-error?
            oracle-error-status
            oracle-error-code))

;;; Credentials, from the environment, as Oracle's API key page gives them.

(define (variable name)
  (or (getenv name)
      (error (string-append "no Oracle credentials: set " name))))

(define (region) (variable "OCI_REGION"))

(define (key-id)
  (string-append (variable "OCI_TENANCY") "/" (variable "OCI_USER") "/"
                 (variable "OCI_FINGERPRINT")))

(define key
  (let ((keys '()))                     ;(file . key), read once
    (lambda ()
      (let ((file (expand-home (variable "OCI_KEY_FILE"))))
        (or (assoc-ref keys file)
            (let ((key (read-rsa-key file)))
              (set! keys (acons file key keys))
              key))))))

(define (oracle-compartment)
  "Return the compartment where resources are made: $OCI_COMPARTMENT, or
else the root compartment of the tenancy."
  (or (getenv "OCI_COMPARTMENT") (variable "OCI_TENANCY")))

;;; Transport.

(define (default-transport method url headers body)
  "Perform an HTTP request; return its status code, its body as a string,
and its headers."
  (receive (response bytes)
      (http-request url #:method method #:headers headers #:body body
                    #:decode-body? #f)
    (values (response-code response)
            (and bytes (utf8->string bytes))
            (response-headers response))))

;; Procedure (method url headers body) -> status, body, headers.  Swapped in
;; tests.
(define oracle-transport (make-parameter default-transport))

;; Procedure called to wait between retries.  Swapped in tests.
(define oracle-sleep (make-parameter sleep))

;;; Errors.

(define &oracle-error
  (make-exception-type '&oracle-error &error '(status code)))

(define make-oracle-error (record-constructor &oracle-error))
(define oracle-error? (exception-predicate &oracle-error))
(define oracle-error-status
  (exception-accessor &oracle-error (record-accessor &oracle-error 'status)))
(define oracle-error-code
  (exception-accessor &oracle-error (record-accessor &oracle-error 'code)))

(define (raise-oracle-error status json)
  (raise-exception
   (make-exception (make-oracle-error status (json-ref json "code"))
                   (make-exception-with-message
                    (or (json-ref json "message")
                        (format #f "Oracle API error (HTTP ~a)" status))))))

;;; Requests.

(define (endpoint service)
  (match service
    ('objectstorage
     (string-append "https://objectstorage." (region) ".oraclecloud.com"))
    ('iaas
     (string-append "https://iaas." (region) ".oraclecloud.com/20160918"))
    ('identity
     (string-append "https://identity." (region) ".oraclecloud.com/20160918"))))

(define (header-value name value)
  "Return VALUE as Guile writes it in the header NAME."
  (let ((line (call-with-output-string
                (lambda (port) (write-header name value port)))))
    (string-trim-both (substring line (1+ (string-index line #\:)))
                      char-set:whitespace)))

(define (signed-headers method uri headers body sign-body?)
  "Return HEADERS, with the date and the authorization signing them, for a
request of METHOD to URI carrying BODY, a bytevector or #f.  With
SIGN-BODY?, its length, type and hash are signed too, as most POST and PUT
requests require."
  (let* ((date (current-date 0))
         (body-headers
          (if sign-body?
              `((content-length . ,(bytevector-length body))
                (x-content-sha256 . ,(base64-encode (sha256 body))))
              '()))
         (headers `((date . ,date) ,@body-headers ,@headers))
         (target (string-append (string-downcase (symbol->string method)) " "
                                (uri-path uri)
                                (match (uri-query uri)
                                  (#f "")
                                  (query (string-append "?" query)))))
         (signed `(("date" . ,(header-value 'date date))
                   ("(request-target)" . ,target)
                   ("host" . ,(uri-host uri))
                   ,@(if sign-body?
                         `(("content-length"
                            . ,(number->string (bytevector-length body)))
                           ("content-type"
                            . ,(header-value 'content-type
                                             (assq-ref headers 'content-type)))
                           ("x-content-sha256"
                            . ,(assq-ref headers 'x-content-sha256)))
                         '()))))
    ;; Guile would rewrite a header named 'authorization, dropping the
    ;; quotes Oracle needs; it sends one it does not know as it is.
    `((Authorization . ,(authorization (key) (key-id) signed))
      ,@headers)))

(define (retryable? status)
  (or (= status 429) (>= status 500)))

(define* (oracle-call service method path
                      #:key json data (headers '()) (attempts 3))
  "Call PATH of SERVICE, one of 'objectstorage, 'iaas or 'identity, sending
JSON, encoded, or DATA, a bytevector.  Retry rate limits and server errors.
Return the decoded JSON body of the response, or #f, and its headers."
  (let* ((url (string-append (endpoint service) path))
         (body (if json (string->utf8 (scm->json-string json)) data))
         (headers (if json
                      `((content-type application/json) ,@headers)
                      headers)))
    (let loop ((attempt 1))
      (receive (status text response-headers)
          ((oracle-transport) method url
           (signed-headers method (string->uri url) headers body
                           (and json (memq method '(POST PUT)) #t))
           body)
        (let ((decoded (and text (not (string-null? text))
                            (false-if-exception (json-string->scm text)))))
          (cond ((and (retryable? status) (< attempt attempts))
                 ((oracle-sleep) (expt 2 attempt))
                 (loop (1+ attempt)))
                ((< status 300)
                 (values decoded response-headers))
                (else
                 (raise-oracle-error status decoded))))))))

(define* (oracle-request service method path #:optional json)
  "Like `oracle-call', but only return the decoded body."
  (receive (decoded _) (oracle-call service method path #:json json)
    decoded))

(define (unless-gone thunk)
  "Call THUNK; return #f instead if what it asks for does not exist."
  (guard (e ((and (oracle-error? e) (eqv? 404 (oracle-error-status e)))
             #f))
    (thunk)))

(define (oracle-get service path)
  "GET PATH of SERVICE and return its body, or #f if it does not exist."
  (unless-gone (lambda () (oracle-request service 'GET path))))

(define (oracle-delete service path)
  "DELETE PATH of SERVICE, unless it is already gone."
  (unless-gone (lambda () (oracle-request service 'DELETE path))))

(define oracle-namespace
  (let ((namespaces '()))               ;(region . namespace)
    (lambda ()
      "Return the Object Storage namespace of the tenancy."
      (or (assoc-ref namespaces (region))
          (let ((namespace (oracle-request 'objectstorage 'GET "/n/")))
            (set! namespaces (acons (region) namespace namespaces))
            namespace)))))

(define (physical-name resource-name)
  "Return the name of RESOURCE-NAME at Oracle: suffixed with the stage, so
that stages do not collide."
  (match (current-stage)
    (#f resource-name)
    (stage (string-append resource-name "-" (stage-name stage)))))

(define* (wait-for-state service path states #:key (tries 120) (delay 5))
  "Poll PATH of SERVICE until its lifecycleState is one of STATES, or it is
gone; return it, or #f if it is gone."
  (let loop ((try 1))
    (let ((found (oracle-get service path)))
      (cond ((or (not found)
                 (member (json-ref found "lifecycleState") states))
             found)
            ((>= try tries)
             (error "timed out waiting for" path states
                    (json-ref found "lifecycleState")))
            (else
             ((oracle-sleep) delay)
             (loop (1+ try)))))))
