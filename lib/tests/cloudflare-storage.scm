;; Tests for KV namespaces and D1 databases, against a scripted fake API.

(use-modules (chaudron)
             (chaudron cloudflare)
             (srfi srfi-64)
             (tests fake-api))

(define accounts (cloudflare-ok #((("id" . "a1")))))
(define ok (cloudflare-ok '(("ok" . #t))))

(define schema
  (let ((file (string-append (mkdtemp "/tmp/chaudron-d1-XXXXXX") "/schema.sql")))
    (call-with-output-file file
      (lambda (port)
        (display "CREATE TABLE IF NOT EXISTS hits (n INTEGER);" port)))
    file))

(define* (storage #:key (title #f))
  (quietly
   (lambda ()
     (with-stage "prod"
       (list (output (cloudflare-kv-namespace "cache" #:title title) 'id)
             (output (cloudflare-d1-database "data" #:schema schema) 'id))))))

(test-begin "cloudflare-storage")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates the namespace, the database, and runs the schema"
    '(("kv1" "db1")
      ((GET "/accounts")
       (POST "/accounts/a1/storage/kv/namespaces")
       (GET "/accounts")
       (POST "/accounts/a1/d1/database")
       (POST "/accounts/a1/d1/database/db1/query")))
    (with-api (accounts (cloudflare-ok '(("id" . "kv1") ("title" . "cache-prod")))
               accounts (cloudflare-ok '(("uuid" . "db1") ("name" . "data-prod")))
               ok)
      (list (storage) (routes))))

  (test-equal "names them after the stage, and sends the schema"
    '("cache-prod" "data-prod" "CREATE TABLE IF NOT EXISTS hits (n INTEGER);")
    (list (assoc-ref (body 1) "title")
          (assoc-ref (body 3) "name")
          (assoc-ref (body 4) "sql")))

  (test-equal "only reads them when nothing changed"
    '((GET "/accounts/a1/storage/kv/namespaces/kv1")
      (GET "/accounts/a1/d1/database/db1"))
    (with-api ((cloudflare-ok '(("id" . "kv1") ("title" . "cache-prod")))
               (cloudflare-ok '(("uuid" . "db1") ("name" . "data-prod"))))
      (storage)
      (routes)))

  (test-equal "renames the namespace in place"
    '(PUT "/accounts/a1/storage/kv/namespaces/kv1")
    (with-api ((cloudflare-ok '(("id" . "kv1") ("title" . "cache-prod")))
               ok
               (cloudflare-ok '(("uuid" . "db1") ("name" . "data-prod"))))
      (storage #:title "cache")
      (cadr (routes))))

  (test-equal "runs the schema again when it changes"
    '((GET "/accounts/a1/storage/kv/namespaces/kv1")
      (GET "/accounts/a1/d1/database/db1")
      (POST "/accounts/a1/d1/database/db1/query"))
    (begin
      (call-with-output-file schema
        (lambda (port)
          (display "CREATE TABLE IF NOT EXISTS hits (n INTEGER, at TEXT);"
                   port)))
      (with-api ((cloudflare-ok '(("id" . "kv1") ("title" . "cache")))
                 (cloudflare-ok '(("uuid" . "db1") ("name" . "data-prod")))
                 ok)
        (storage #:title "cache")
        (routes))))

  (test-equal "deletes them"
    '((DELETE "/accounts/a1/d1/database/db1")
      (DELETE "/accounts/a1/storage/kv/namespaces/kv1"))
    (with-api (ok ok)
      (quietly (lambda () (with-stage "prod" #t)))
      (routes))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "cloudflare-storage")
(exit (zero? failures))
