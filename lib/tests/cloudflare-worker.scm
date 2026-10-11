;; Tests for Cloudflare Workers serving static files, against a scripted
;; fake API.

(use-modules (chaudron)
             (chaudron cloudflare)
             (chaudron resource)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (gcrypt base16)
             (gcrypt base64)
             (gcrypt hash)
             (rnrs bytevectors)
             (srfi srfi-64)
             (tests fake-api))

(define site (mkdtemp "/tmp/chaudron-site-XXXXXX"))

(define (write-file! name text)
  (call-with-output-file (string-append site "/" name)
    (lambda (port) (display text port))))

(write-file! "index.html" "<h1>Hello</h1>")
(write-file! "style.css" "h1 { color: green }")
(write-file! ".hidden" "not served")

(define (cloudflare-hash text extension)
  "The hash Cloudflare gives a file holding TEXT: 32 hexadecimal digits of
the SHA-256 of TEXT in base64 followed by EXTENSION."
  (string-take (bytevector->base16-string
                (sha256 (string->utf8
                         (string-append (base64-encode (string->utf8 text))
                                        extension))))
               32))

(define* (worker #:key (domain "www.example.com"))
  (quietly
   (lambda ()
     (with-stage "prod"
       (cloudflare-worker "site" #:assets site #:domain domain)))))

(define accounts (cloudflare-ok #((("id" . "a1")))))

(define* (session #:key (buckets #()))
  (cloudflare-ok `(("jwt" . "session-token") ("buckets" . ,buckets))))

(define no-zone (cloudflare-ok #()))
(define zone (cloudflare-ok #((("id" . "z1") ("name" . "example.com")))))
(define domain (cloudflare-ok '(("id" . "d1"))))
(define ok (cloudflare-ok '(("ok" . #t))))

(test-begin "cloudflare-worker")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "uploads the files, publishes the Worker and serves it at its domain"
    '("https://www.example.com/"
      ((GET "/accounts")
       (POST "/accounts/a1/workers/scripts/site-prod/assets-upload-session")
       (POST "/accounts/a1/workers/assets/upload?base64=true")
       (POST "/accounts/a1/workers/assets/upload?base64=true")
       (PUT "/accounts/a1/workers/scripts/site-prod")
       (GET "/zones?name=www.example.com")
       (GET "/zones?name=example.com")
       (PUT "/accounts/a1/workers/domains")))
    (with-api (accounts
               (session #:buckets
                        (vector (vector (cloudflare-hash "<h1>Hello</h1>" "html"))
                                (vector (cloudflare-hash "h1 { color: green }"
                                                         "css"))))
               (cloudflare-ok '(("ok" . #t)))
               (cloudflare-ok '(("jwt" . "done-token")))
               ok no-zone zone domain)
      (list (output (worker) 'url) (routes))))

  (test-equal "lists every file but hidden ones, with their hash and size"
    `(("/index.html" ("hash" . ,(cloudflare-hash "<h1>Hello</h1>" "html"))
                     ("size" . 14))
      ("/style.css" ("hash" . ,(cloudflare-hash "h1 { color: green }" "css"))
                    ("size" . 19)))
    (sort (map (lambda (entry)
                 (cons (car entry) (sort (cdr entry)
                                         (lambda (a b) (string<? (car a) (car b))))))
               (assoc-ref (body 1) "manifest"))
          (lambda (a b) (string<? (car a) (car b)))))

  (test-assert "uploads each file in base64, with its content type"
    (let ((upload (body 2)))
      (and (string-contains upload (base64-encode (string->utf8 "<h1>Hello</h1>")))
           (string-contains upload "Content-Type: text/html"))))

  (test-assert "publishes the Worker with the token of the last upload"
    (string-contains (body 4) "done-token"))

  (test-equal "serves it at its domain"
    '("www.example.com" "site-prod" "z1")
    (map (lambda (key) (assoc-ref (body 7) key))
         '("hostname" "service" "zone_id")))

  (test-equal "only checks the Worker when nothing changed"
    '((GET "/accounts/a1/workers/scripts/site-prod/settings"))
    (with-api (ok)
      (worker)
      (routes)))

  (test-equal "publishes again when a file changes, without uploading what Cloudflare has"
    '((GET "/accounts/a1/workers/scripts/site-prod/settings")
      (POST "/accounts/a1/workers/scripts/site-prod/assets-upload-session")
      (PUT "/accounts/a1/workers/scripts/site-prod"))
    (begin
      (write-file! "index.html" "<h1>Hello again</h1>")
      (with-api (ok (session) ok)
        (worker)
        (routes))))

  (test-equal "deletes its domain, then the Worker"
    '((DELETE "/accounts/a1/workers/domains/d1")
      (DELETE "/accounts/a1/workers/scripts/site-prod?force=true"))
    ;; Deleting a domain answers with no body at all.
    (with-api ('(200 . #f) ok)
      (quietly (lambda () (with-stage "prod" #t)))
      (routes))))

;; A Worker running code, given variables, a secret, a KV namespace and
;; times to run.

(define script (string-append site "/worker.js"))

(call-with-output-file script
  (lambda (port) (display "export default { fetch() {} };" port)))

(setenv "CHAUDRON_TEST_TOKEN" "very-secret")

(define* (api #:key (greeting "hello") (crons '("*/30 * * * *")))
  (quietly
   (lambda ()
     (with-stage "prod"
       (let ((cache (make-resource 'cloudflare-kv-namespace "cache" '()
                                   '((id . "kv1")))))
         (cloudflare-worker "api"
                            #:script script
                            #:vars `(("GREETING" . ,greeting))
                            #:secrets '("CHAUDRON_TEST_TOKEN")
                            #:bindings (list (kv-binding "CACHE" cache))
                            #:crons crons))))))

(define subdomain (cloudflare-ok '(("subdomain" . "me"))))

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "publishes the code, then its schedule, on workers.dev"
    '("https://api-prod.me.workers.dev/"
      ((GET "/accounts")
       (PUT "/accounts/a1/workers/scripts/api-prod")
       (PUT "/accounts/a1/workers/scripts/api-prod/schedules")
       (POST "/accounts/a1/workers/scripts/api-prod/subdomain")
       (GET "/accounts/a1/workers/subdomain")))
    (with-api (accounts ok ok ok subdomain)
      (list (output (api) 'url) (routes))))

  (test-assert "sends the module, the variables, the secret and the binding"
    (let ((upload (body 1)))
      (every (lambda (text) (string-contains upload text))
             '("\"main_module\":\"worker.js\""
               "export default { fetch() {} };"
               "\"type\":\"plain_text\",\"name\":\"GREETING\",\"text\":\"hello\""
               "\"type\":\"secret_text\",\"name\":\"CHAUDRON_TEST_TOKEN\",\"text\":\"very-secret\""
               "\"type\":\"kv_namespace\",\"name\":\"CACHE\",\"namespace_id\":\"kv1\""))))

  (test-equal "runs it at the times given"
    #((("cron" . "*/30 * * * *")))
    (body 2))

  (test-assert "does not save the secret"
    (not (string-contains
          (call-with-input-file
              (string-append (state-directory)
                             "/prod/cloudflare-worker/api.scm")
            get-string-all)
          "very-secret")))

  (test-equal "publishes again when a variable changes"
    '((GET "/accounts/a1/workers/scripts/api-prod/settings")
      (PUT "/accounts/a1/workers/scripts/api-prod"))
    (with-api (ok ok)
      (api #:greeting "bonjour")
      (routes)))

  (test-equal "only changes the schedule when the times change"
    '((GET "/accounts/a1/workers/scripts/api-prod/settings")
      (PUT "/accounts/a1/workers/scripts/api-prod/schedules"))
    (with-api (ok ok)
      (api #:greeting "bonjour" #:crons '("0 3 * * *"))
      (routes)))

  (test-equal "publishes again when the secret changes"
    '((GET "/accounts/a1/workers/scripts/api-prod/settings")
      (PUT "/accounts/a1/workers/scripts/api-prod"))
    (begin
      (setenv "CHAUDRON_TEST_TOKEN" "another-secret")
      (with-api (ok ok)
        (api #:greeting "bonjour" #:crons '("0 3 * * *"))
        (routes)))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "cloudflare-worker")
(exit (zero? failures))
