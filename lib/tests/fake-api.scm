;;; A scripted fake of the Hetzner Cloud and Cloudflare APIs, for tests.

(define-module (tests fake-api)
  #:use-module (chaudron)
  #:use-module (chaudron cloudflare api)
  #:use-module (chaudron hetzner api)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:export (call-with-api
            with-api
            recorded-requests
            routes
            body
            action
            done
            ok
            cloudflare-ok
            quietly))

(define %endpoints
  '("https://api.hetzner.cloud/v1" "https://api.cloudflare.com/client/v4"))

(define (url->path url)
  (let ((endpoint (find (lambda (endpoint) (string-prefix? endpoint url))
                        %endpoints)))
    (string-drop url (string-length endpoint))))

(define requests '())                   ;(method path body headers)
(define responses '())                  ;(status . json), consumed in order

(define (fake-transport method url headers body)
  (set! requests
        (append requests
                (list (list method
                            (url->path url)
                            ;; Multipart bodies are kept as they are.
                            (and body (or (false-if-exception
                                           (json-string->scm body))
                                          body))
                            headers))))
  (when (null? responses)
    (error "unexpected request" method url))
  (let ((response (car responses)))
    (set! responses (cdr responses))
    (values (car response)
            (and (cdr response) (scm->json-string (cdr response))))))

(define (call-with-api scripted-responses thunk)
  "Call THUNK with the API answering SCRIPTED-RESPONSES, in order."
  (set! requests '())
  (set! responses scripted-responses)
  (parameterize ((hetzner-transport fake-transport)
                 (hetzner-token "secret")
                 (hetzner-sleep (const #t))
                 (cloudflare-transport fake-transport)
                 (cloudflare-token "secret")
                 (cloudflare-sleep (const #t))
                 (exit-on-failure? #f))
    (thunk)))

(define-syntax-rule (with-api (response ...) body ...)
  (call-with-api (list response ...) (lambda () body ...)))

(define (recorded-requests)
  requests)

(define (routes)
  "Return the method and path of each request made so far."
  (map (lambda (request) (list (car request) (cadr request))) requests))

(define (body n)
  "Return the decoded JSON body of request N."
  (caddr (list-ref requests n)))

(define (action id status)
  `(("id" . ,id) ("status" . ,status)))

(define (done id)
  "A response carrying the successful action ID."
  `(200 . (("action" . ,(action id "success")))))

(define (ok key json)
  "A successful response carrying JSON under KEY."
  `(200 . ((,key . ,json))))

(define (cloudflare-ok result)
  "A successful Cloudflare response carrying RESULT."
  `(200 . (("success" . #t) ("errors" . #()) ("result" . ,result))))

(define (quietly thunk)
  "Call THUNK, discarding what chaudron reports."
  (parameterize ((current-error-port (%make-void-port "w")))
    (thunk)))
