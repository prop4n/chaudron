;; Tests for the Hetzner provider, against a scripted fake HTTP transport.

(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron hetzner api)
             (ice-9 exceptions)
             (json)
             (srfi srfi-43)
             (srfi srfi-64))

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
  (let ((response (car responses)))
    (set! responses (cdr responses))
    (values (car response)
            (and (cdr response) (scm->json-string (cdr response))))))

(define-syntax-rule (with-api (response ...) body ...)
  (begin
    (set! requests '())
    (set! responses (list response ...))
    (parameterize ((hetzner-transport fake-transport)
                   (hetzner-token "secret")
                   (hetzner-sleep (const #t)))
      body ...)))

(define (routes)
  (map (lambda (request) (list (car request) (cadr request))) requests))

(define (body n)
  (caddr (list-ref requests n)))

(define (action id status)
  `(("id" . ,id) ("status" . ,status)))

(define (done id)
  `(200 . (("action" . ,(action id "success")))))

(define %public-key "ssh-ed25519 AAAA moi@forge")

(define* (server-json #:key (type "cx22"))
  `(("id" . 42)
    ("name" . "forge")
    ("server_type" . (("name" . ,type)))
    ("public_net" . (("ipv4" . (("ip" . "1.2.3.4")))
                     ("ipv6" . (("ip" . "2a01::/64")))))))

(define* (infra #:key (type "cx22") (firewall? #t))
  (with-stage "prod"
    (let* ((key (hetzner-ssh-key "moi" #:public-key %public-key))
           (web (and firewall?
                     (hetzner-firewall "web" #:rules (list (allow-in 'tcp 22))))))
      (hetzner-server "forge" #:type type #:location "fsn1"
                      #:ssh-keys (list key)
                      #:firewalls (if web (list web) '())
                      #:user-data "#cloud-config"))))

(define reads
  ;; Responses to the reads done at the start of a run.
  (list `(200 . (("ssh_key" . (("id" . 7) ("name" . "moi")
                               ("fingerprint" . "aa")))))
        `(200 . (("firewall" . (("id" . 3) ("name" . "web")))))))

(define read-routes
  '((GET "/ssh_keys/7") (GET "/firewalls/3") (GET "/servers/42")))

(define-syntax-rule (with-reads (response ...) body ...)
  (begin
    (set! requests '())
    (set! responses (append reads (list response ...)))
    (parameterize ((hetzner-transport fake-transport)
                   (hetzner-token "secret")
                   (hetzner-sleep (const #t)))
      body ...)))

(define (quietly thunk)
  (parameterize ((current-error-port (%make-void-port "w")))
    (thunk)))

(test-begin "hetzner")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates the ssh key, the firewall and the server"
    '("1.2.3.4" (POST "/ssh_keys") (POST "/firewalls") (POST "/servers")
      (GET "/actions/1") (GET "/actions/2"))
    (with-api (`(201 . (("ssh_key" . (("id" . 7) ("fingerprint" . "aa")))))
               `(201 . (("firewall" . (("id" . 3)))
                        ("actions" . #())))
               `(201 . (("server" . ,(server-json))
                        ("action" . ,(action 1 "running"))
                        ("next_actions" . #(,(action 2 "running")))))
               (done 1)
               (done 2))
      (cons (output (quietly infra) 'ipv4) (routes))))

  (test-equal "sends the expected payloads"
    '("ssh-ed25519 AAAA moi@forge" "prod"
      #((("direction" . "in") ("protocol" . "tcp") ("port" . "22")
         ("source_ips" . #("0.0.0.0/0" "::/0"))))
      "cx22" #(7) #((("firewall" . 3))) "#cloud-config")
    (list (assoc-ref (body 0) "public_key")
          (assoc-ref (assoc-ref (body 0) "labels") "chaudron/stage")
          (vector-map (lambda (_ rule) (reverse rule))
                      (assoc-ref (body 1) "rules"))
          (assoc-ref (body 2) "server_type")
          (assoc-ref (body 2) "ssh_keys")
          (assoc-ref (body 2) "firewalls")
          (assoc-ref (body 2) "user_data")))

  (test-equal "authenticates with the token"
    '(bearer secret)
    (assq-ref (cadddr (car requests)) 'authorization))

  (test-equal "only reads when nothing changed"
    read-routes
    (with-reads (`(200 . (("server" . ,(server-json)))))
      (quietly infra)
      (routes)))

  (test-equal "resizes the server in place"
    (append read-routes
            '((POST "/servers/42/actions/poweroff")
              (POST "/servers/42/actions/change_type")
              (POST "/servers/42/actions/poweron")))
    (with-reads (`(200 . (("server" . ,(server-json))))
                 (done 3) (done 4) (done 5))
      (quietly (lambda () (infra #:type "cx32")))
      (routes)))

  (test-equal "corrects a resize made behind its back"
    (append read-routes
            '((POST "/servers/42/actions/poweroff")
              (POST "/servers/42/actions/change_type")
              (POST "/servers/42/actions/poweron")))
    (with-reads (`(200 . (("server" . ,(server-json #:type "cx42"))))
                 (done 3) (done 4) (done 5))
      (quietly (lambda () (infra #:type "cx32")))
      (routes)))

  (test-equal "recreates a server deleted behind its back"
    (append read-routes '((POST "/servers")))
    (with-reads ('(404 . (("error" . (("code" . "not_found")))))
                 `(201 . (("server" . ,(server-json #:type "cx32"))
                          ("action" . ,(action 6 "success")))))
      (quietly (lambda () (infra #:type "cx32")))
      (routes)))

  (test-equal "detaches and deletes a firewall that is no longer declared"
    '((GET "/ssh_keys/7") (GET "/servers/42")
      (POST "/firewalls/3/actions/remove_from_resources")
      (DELETE "/firewalls/3"))
    (with-api ((car reads)
               `(200 . (("server" . ,(server-json #:type "cx32"))))
               `(201 . (("actions" . #(,(action 7 "success")))))
               '(204 . #f))
      (quietly (lambda () (infra #:type "cx32" #:firewall? #f)))
      (routes)))

  (test-equal "deletes orphans, tolerating resources already gone"
    '((DELETE "/servers/42") (DELETE "/ssh_keys/7"))
    (with-api ('(404 . (("error" . (("code" . "not_found")
                                   ("message" . "server not found")))))
               '(204 . #f))
      (quietly (lambda () (with-stage "prod" #t)))
      (routes)))

  (test-equal "reads the public key from a file"
    "ssh-ed25519 BBBB"
    (let ((file (string-append (state-directory) "/key.pub")))
      (call-with-output-file file
        (lambda (port) (display "ssh-ed25519 BBBB\n" port)))
      (with-api (`(201 . (("ssh_key" . (("id" . 8))))))
        (quietly
         (lambda ()
           (with-stage "files"
             (hetzner-ssh-key "file" #:public-key-file file))))
        (assoc-ref (body 0) "public_key"))))

  (test-equal "retries on server errors"
    '(("ok" . #t))
    (with-api ('(503 . #f) '(200 . (("ok" . #t))))
      (hetzner-request 'GET "/servers")))

  (test-equal "raises API errors"
    '(422 "invalid_input" "bad type")
    (with-api ('(422 . (("error" . (("code" . "invalid_input")
                                   ("message" . "bad type"))))))
      (guard (e ((hetzner-error? e)
                 (list (hetzner-error-status e)
                       (hetzner-error-code e)
                       (exception-message e))))
        (hetzner-request 'POST "/servers"))))

  (test-equal "raises when an action fails"
    "action_failed"
    (with-api ()
      (guard (e ((hetzner-error? e) (hetzner-error-code e)))
        (wait-for-action `(("id" . 9) ("status" . "error")
                           ("error" . (("code" . "action_failed")
                                       ("message" . "nope")))))))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "hetzner")
(exit (zero? failures))
