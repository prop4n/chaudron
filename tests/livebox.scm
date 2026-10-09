;; Tests for the Livebox provider, against a scripted fake of its API.

(use-modules (chaudron)
             (chaudron livebox)
             (chaudron livebox api)
             (ice-9 exceptions)
             (ice-9 match)
             (json)
             (srfi srfi-64))

;;; A fake Livebox.

(define calls '())                      ;(service method parameters)
(define headers '())                    ;the headers of each request
(define responses '())                  ;JSON objects, consumed in order

(define (fake-transport method url request-headers body)
  (let ((request (json-string->scm body)))
    (set! calls (append calls (list (list (assoc-ref request "service")
                                          (assoc-ref request "method")
                                          (assoc-ref request "parameters")))))
    (set! headers (append headers (list request-headers))))
  (match responses
    ((response . rest)
     (set! responses rest)
     (values 200 (scm->json-string response) "sess/sessid=abc; Path=/"))
    (() (error "unexpected request" body))))

(define login '(("status" . 0) ("data" . (("contextID" . "ctx")))))

(define-syntax-rule (with-livebox (response ...) body ...)
  (begin
    (set! calls '())
    (set! headers '())
    (set! responses (list response ...))
    (parameterize ((livebox-transport fake-transport)
                   (livebox-password "secret")
                   (exit-on-failure? #f)
                   (current-error-port (%make-void-port "w")))
      body ...)))

(define (methods)
  (map cadr calls))

(define (parameters n)
  (caddr (list-ref calls n)))

(define* (rule #:key (to "192.168.1.202") (port "443"))
  `(("Id" . "webui_headscale") ("ExternalPort" . ,port) ("InternalPort" . ,port)
    ("DestinationIPAddress" . ,to) ("Protocol" . "6,17") ("Enable" . #t)))

(define* (rules #:optional (rules (list (rule))))
  `(("status" . ,(map (lambda (rule) (cons (assoc-ref rule "Id") rule)) rules))))

(define* (headscale #:key (to "192.168.1.202"))
  (with-stage "home"
    (livebox-port-forward "headscale" #:port 443 #:to to #:protocol 'both)))

(define* (leases . leases)
  `(("status" . ,(list->vector leases))))

(define* (server #:key (ip "192.168.1.200"))
  (with-stage "home"
    (livebox-dhcp-lease "server" #:mac "AA:BB:CC:00:11:22" #:ip ip)))

(test-begin "livebox")

(forget-livebox-session!)

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "logs in, then creates a port forward"
    '(("createContext" "setPortForwarding")
      ("headscale" "6,17" "443" "443" "192.168.1.202" #t)
      "webui_headscale")
    (with-livebox (login '(("status" . "webui_headscale")))
      (let ((forward (headscale)))
        (list (methods)
              (map (lambda (key) (assoc-ref (parameters 1) key))
                   '("id" "protocol" "externalPort" "internalPort"
                     "destinationIPAddress" "enable"))
              (output forward 'id)))))

  (test-equal "authenticates with the session's context and cookie"
    '((x-sah-login) (x-sah ctx) "sess/sessid=abc")
    (list (assq-ref (car headers) 'authorization)
          (assq-ref (cadr headers) 'authorization)
          (assq-ref (cadr headers) 'cookie)))

  (test-equal "only reads when nothing changed, in the same session"
    '("getPortForwarding")
    (with-livebox ((rules))
      (headscale)
      (methods)))

  (test-equal "updates a rule in place"
    '("getPortForwarding" "setPortForwarding")
    (with-livebox ((rules) '(("status" . "webui_headscale")))
      (headscale #:to "192.168.1.205")
      (methods)))

  (test-equal "recreates a rule deleted behind its back"
    '("getPortForwarding" "setPortForwarding")
    (with-livebox ((rules '()) '(("status" . "webui_headscale")))
      (headscale #:to "192.168.1.205")
      (methods)))

  (test-equal "deletes rules that are no longer declared"
    '("getPortForwarding" "deletePortForwarding")
    (with-livebox ((rules (list (rule #:to "192.168.1.205")))
                   '(("status" . #t)))
      (with-stage "home" #t)
      (methods)))

  (test-equal "adds a static lease"
    '(("addStaticLease") ("aa:bb:cc:00:11:22" "192.168.1.200"))
    (with-livebox ('(("status" . null)))
      (server)
      (list (methods)
            (map (lambda (key) (assoc-ref (parameters 0) key))
                 '("MACAddress" "IPAddress")))))

  (test-equal "renews an expired session"
    '("getStaticLeases" "createContext" "getStaticLeases")
    (with-livebox ('(("status" . #f)
                     ("errors" . #((("error" . 13)
                                    ("description" . "Permission denied")))))
                   login
                   (leases '(("MACAddress" . "AA:BB:CC:00:11:22")
                             ("IPAddress" . "192.168.1.200"))))
      (server)
      (methods)))

  (test-equal "replaces a lease whose address changed"
    '(("getStaticLeases" "getStaticLeases" "deleteStaticLease" "addStaticLease")
      "192.168.1.201")
    (with-livebox ((leases '(("MACAddress" . "AA:BB:CC:00:11:22")
                             ("IPAddress" . "192.168.1.200")))
                   (leases '(("MACAddress" . "AA:BB:CC:00:11:22")
                             ("IPAddress" . "192.168.1.200")))
                   '(("status" . null))
                   '(("status" . null)))
      (server #:ip "192.168.1.201")
      (list (methods) (assoc-ref (parameters 3) "IPAddress"))))

  (test-assert "raises the Livebox's errors"
    (with-livebox ('(("status" . #f)
                     ("errors" . #((("error" . 1) ("description" . "boom")))))
                   login
                   '(("status" . #f)
                     ("errors" . #((("error" . 1) ("description" . "boom"))))))
      (guard (e ((livebox-error? e)
                 (string-contains (exception-message e) "Livebox: boom")))
        (server #:ip "192.168.1.202")
        #f))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "livebox")
(exit (zero? failures))
