;;; Cloudflare D1 databases.

(define-module (chaudron cloudflare d1)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron cloudflare api)
  #:use-module (gcrypt base16)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 match)
  #:use-module (ice-9 textual-ports)
  #:export (cloudflare-d1-database))

(define (database-path outputs . rest)
  (apply string-append "/accounts/" (assq-ref outputs 'account-id)
         "/d1/database/" (assq-ref outputs 'id) rest))

(define (apply-schema! outputs schema)
  "Run the SQL statements of the file SCHEMA in the database."
  (cloudflare-request 'POST (database-path outputs "/query")
                      `(("sql" . ,(call-with-input-file schema
                                    get-string-all)))))

(define (create-database _ props)
  (let* ((account (account-id))
         (database (cloudflare-request
                    'POST (string-append "/accounts/" account "/d1/database")
                    `(("name" . ,(assq-ref props 'name)))))
         (outputs `((id . ,(json-ref database "uuid"))
                    (account-id . ,account))))
    (when (assq-ref props 'schema)
      (created! outputs props '((schema-hash . #f)))
      (apply-schema! outputs (assq-ref props 'schema)))
    outputs))

(define (read-database outputs)
  (and=> (cloudflare-get (database-path outputs))
         (lambda (database)
           (cons `((name . ,(json-ref database "name"))) outputs))))

(define (update-database outputs old new)
  ;; Only the schema can change in place: it is run again.
  (when (assq-ref new 'schema)
    (apply-schema! outputs (assq-ref new 'schema)))
  outputs)

(define (delete-database outputs)
  (cloudflare-delete (database-path outputs)))

(define database-provider
  (register-provider!
   (make-provider 'cloudflare-d1-database
                  #:create create-database
                  #:read read-database
                  #:update update-database
                  #:delete delete-database
                  #:replace-on '(name))))

(define (file-digest file)
  (bytevector->base16-string
   (sha256 (call-with-input-file file get-bytevector-all #:binary #t))))

(define* (cloudflare-d1-database resource-name #:key schema name)
  "Declare a D1 database, SQLite for Workers, given to them with
`d1-binding'.  It is named after RESOURCE-NAME and the stage, or NAME;
changing its name replaces it, losing its data.  SCHEMA is a file of SQL
statements, run when the database is created and whenever the file
changes: they must be safe to run again, such as CREATE TABLE IF NOT
EXISTS."
  (ensure-resource database-provider resource-name
                   `((name . ,(or name
                                  (match (current-stage)
                                    (#f resource-name)
                                    (stage (string-append
                                            resource-name "-"
                                            (stage-name stage))))))
                     (schema . ,schema)
                     (schema-hash . ,(and schema (file-digest schema))))))
