;; Tests for the Hetzner provider, against a scripted fake HTTP transport.

(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron hetzner api)
             (ice-9 exceptions)
             (json)
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

(define* (infra #:key (type "cx22"))
  (with-stage "prod"
    (let ((key (hetzner-ssh-key "moi" #:public-key %public-key)))
      (hetzner-server "forge" #:type type #:location "fsn1"
                      #:ssh-keys (list key)))))

(test-begin "hetzner")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates the ssh key and the server"
    '("1.2.3.4" (POST "/ssh_keys") (POST "/servers")
      (GET "/actions/1") (GET "/actions/2"))
    (with-api (`(201 . (("ssh_key" . (("id" . 7) ("fingerprint" . "aa")))))
               `(201 . (("server"
                        . (("id" . 42)
                           ("public_net"
                            . (("ipv4" . (("ip" . "1.2.3.4")))
                               ("ipv6" . (("ip" . "2a01::/64")))))))
                       ("action" . ,(action 1 "running"))
                       ("next_actions" . #(,(action 2 "running")))))
               (done 1)
               (done 2))
      (cons (output (infra) 'ipv4) (routes))))

  (test-equal "sends the expected payloads"
    '("ssh-ed25519 AAAA moi@forge" "prod" "cx22" #(7))
    (list (assoc-ref (body 0) "public_key")
          (assoc-ref (assoc-ref (body 0) "labels") "chaudron/stage")
          (assoc-ref (body 1) "server_type")
          (assoc-ref (body 1) "ssh_keys")))

  (test-equal "authenticates with the token"
    '(bearer secret)
    (assq-ref (cadddr (car requests)) 'authorization))

  (test-equal "does nothing when nothing changed"
    '()
    (with-api () (infra) (routes)))

  (test-equal "resizes the server in place"
    '((POST "/servers/42/actions/poweroff")
      (POST "/servers/42/actions/change_type")
      (POST "/servers/42/actions/poweron"))
    (with-api ((done 3) (done 4) (done 5))
      (infra #:type "cx32")
      (routes)))

  (test-equal "deletes orphans, tolerating resources already gone"
    '((DELETE "/servers/42") (DELETE "/ssh_keys/7"))
    (with-api ('(404 . (("error" . (("code" . "not_found")
                                   ("message" . "server not found")))))
               '(204 . #f))
      (with-stage "prod" #t)
      (routes)))

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
