;;; Minimal client for the API of Orange's Livebox.  It is undocumented: what
;;; is here was checked against a Livebox Fibre.

(define-module (chaudron livebox api)
  #:use-module (chaudron http)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 threads)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (web client)
  #:use-module (web http)
  #:use-module (web response)
  #:re-export (json-ref
               json-list)
  #:export (livebox-host
            livebox-username
            livebox-password
            livebox-transport
            livebox-call
            forget-livebox-session!

            livebox-error?
            livebox-error-code))

(define livebox-host (make-parameter "192.168.1.1"))

;; Credentials; when unset, $LIVEBOX_USERNAME (or "admin") and
;; $LIVEBOX_PASSWORD are used.
(define livebox-username (make-parameter #f))
(define livebox-password (make-parameter #f))

(define (http-transport/cookie method url headers body)
  "Like `http-transport', also returning the cookie the response sets."
  (receive (response bytes)
      (http-request url #:method method #:headers headers
                    #:body (and body (string->utf8 body))
                    #:decode-body? #f)
    (values (response-code response)
            (and bytes (utf8->string bytes))
            (assq-ref (response-headers response) 'set-cookie))))

;; Procedure (method url headers body) -> status, body, cookie.  Swapped in
;; tests.
(define livebox-transport (make-parameter http-transport/cookie))

;;; Errors.

(define &livebox-error
  (make-exception-type '&livebox-error &error '(code)))

(define make-livebox-error (record-constructor &livebox-error))
(define livebox-error? (exception-predicate &livebox-error))
(define livebox-error-code
  (exception-accessor &livebox-error (record-accessor &livebox-error 'code)))

(define (raise-livebox-error error)
  (raise-exception
   (make-exception (make-livebox-error (json-ref error "error"))
                   (make-exception-with-message
                    (string-append "Livebox: "
                                   (or (json-ref error "description")
                                       "request failed"))))))

;;; Sessions.

(define (url)
  (string-append "http://" (livebox-host) "/ws"))

(define %content-type '(application/x-sah-ws-4-call+json))

(define (post authorization cookie body)
  "Send BODY, a JSON object; return the decoded response and its cookie."
  (receive (status text cookie)
      ((livebox-transport)
       'POST (url)
       `((content-type . ,%content-type)
         (authorization . ,(parse-header 'authorization authorization))
         ,@(if cookie `((cookie . ,cookie)) '()))
       (scm->json-string body))
    (let ((json (and text (false-if-exception (json-string->scm text)))))
      (match (json-list json "errors")
        ((error . _) (raise-livebox-error error))
        (()
         (unless (< status 300)
           (raise-livebox-error
            `(("description" . ,(format #f "HTTP ~a" status)))))
         (values json cookie))))))

(define (login)
  "Open a session; return its context and cookie."
  (receive (json cookie)
      (post "X-Sah-Login" #f
            `(("service" . "sah.Device.Information")
              ("method" . "createContext")
              ("parameters"
               . (("applicationName" . "webui")
                  ("username" . ,(or (livebox-username)
                                     (getenv "LIVEBOX_USERNAME")
                                     "admin"))
                  ("password" . ,(or (livebox-password)
                                     (getenv "LIVEBOX_PASSWORD")
                                     (error "no Livebox password: set \
LIVEBOX_PASSWORD")))))))
    (match (json-ref json "data" "contextID")
      ((? string? context)
       (cons context (car (string-split (or cookie "") #\;))))
      (_ (raise-livebox-error
          '(("description" . "login failed, check the credentials")))))))

;; The open session, shared by threads.
(define %session #f)
(define %session-lock (make-mutex))

(define (session)
  (with-mutex %session-lock
    (or %session
        (begin (set! %session (login)) %session))))

(define (forget-livebox-session!)
  (with-mutex %session-lock
    (set! %session #f)))

(define* (livebox-call service method #:optional (parameters '()))
  "Call METHOD of SERVICE with PARAMETERS, an alist, and return the decoded
response.  An expired session is renewed once."
  (define (attempt)
    (match (session)
      ((context . cookie)
       (receive (json _)
           (post (string-append "X-Sah " context) cookie
                 `(("service" . ,service)
                   ("method" . ,method)
                   ("parameters" . ,parameters)))
         json))))

  (guard (e ((livebox-error? e)
             (forget-livebox-session!)
             (attempt)))
    (attempt)))
