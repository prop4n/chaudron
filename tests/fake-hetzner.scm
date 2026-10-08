;;; A scripted fake of the Hetzner Cloud API, for tests.

(define-module (tests fake-hetzner)
  #:use-module (chaudron hetzner api)
  #:use-module (json)
  #:export (call-with-api
            with-api
            recorded-requests
            routes
            body
            action
            done
            ok
            quietly))

(define %endpoint "https://api.hetzner.cloud/v1")

(define requests '())                   ;(method path body headers)
(define responses '())                  ;(status . json), consumed in order

(define (fake-transport method url headers body)
  (set! requests
        (append requests
                (list (list method
                            (string-drop url (string-length %endpoint))
                            (and body (json-string->scm body))
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
                 (hetzner-sleep (const #t)))
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

(define (quietly thunk)
  "Call THUNK, discarding what chaudron reports."
  (parameterize ((current-error-port (%make-void-port "w")))
    (thunk)))
