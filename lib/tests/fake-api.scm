;;; A scripted fake of the Hetzner Cloud, Cloudflare and Oracle Cloud APIs,
;;; for tests.

(define-module (tests fake-api)
  #:use-module (chaudron)
  #:use-module (chaudron cloudflare api)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron oracle api)
  #:use-module (ice-9 receive)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:export (call-with-api
            with-api
            recorded-requests
            routes
            body
            action
            done
            ok
            cloudflare-ok
            with-headers
            quietly))

(define %endpoints
  '("https://api.hetzner.cloud/v1" "https://api.hetzner.com/v1"
    "https://api.cloudflare.com/client/v4"
    "https://objectstorage.xx-test-1.oraclecloud.com"
    "https://iaas.xx-test-1.oraclecloud.com/20160918"
    "https://identity.xx-test-1.oraclecloud.com/20160918"))

(define (url->path url)
  (let ((endpoint (find (lambda (endpoint) (string-prefix? endpoint url))
                        %endpoints)))
    (string-drop url (string-length endpoint))))

(define requests '())                   ;(method path body headers)
(define responses '())                  ;(status . json), consumed in order

;; A response that also has headers, for Oracle.
(define-record-type <headed>
  (with-headers headers response)
  headed?
  (headers headed-headers)
  (response headed-response))

(define (next-response! method url headers body)
  "Record the request, and return the next scripted response: its status,
its body as a string, and its headers."
  (set! requests
        (append requests
                (list (list method
                            (url->path url)
                            ;; Multipart and binary bodies are kept as they
                            ;; are.
                            (and body (or (false-if-exception
                                           (json-string->scm
                                            (if (bytevector? body)
                                                (utf8->string body)
                                                body)))
                                          body))
                            headers))))
  (when (null? responses)
    (error "unexpected request" method url))
  (let* ((response (car responses))
         (headers (if (headed? response) (headed-headers response) '()))
         (response (if (headed? response) (headed-response response) response)))
    (set! responses (cdr responses))
    (values (car response)
            (and (cdr response) (scm->json-string (cdr response)))
            headers)))

(define (fake-transport method url headers body)
  (receive (status text _) (next-response! method url headers body)
    (values status text)))

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
                 (oracle-transport next-response!)
                 (oracle-sleep (const #t))
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
