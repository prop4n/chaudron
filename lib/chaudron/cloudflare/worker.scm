;;; Cloudflare Workers: code, static files, and what the code is given.

(define-module (chaudron cloudflare worker)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron cloudflare api)
  #:use-module (gcrypt base16)
  #:use-module (gcrypt base64)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 match)
  #:use-module (ice-9 textual-ports)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:export (cloudflare-worker
            kv-binding
            d1-binding))

(define %compatibility-date "2025-01-01")

;;; The files to serve.

(define %content-types
  '(("html" . "text/html") ("htm" . "text/html") ("css" . "text/css")
    ("js" . "text/javascript") ("mjs" . "text/javascript")
    ("json" . "application/json") ("xml" . "application/xml")
    ("txt" . "text/plain") ("svg" . "image/svg+xml") ("png" . "image/png")
    ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg") ("gif" . "image/gif")
    ("webp" . "image/webp") ("ico" . "image/x-icon")
    ("pdf" . "application/pdf") ("woff" . "font/woff")
    ("woff2" . "font/woff2") ("wasm" . "application/wasm")))

(define (extension file)
  "The extension of FILE, without the dot, or \"\"."
  (let ((name (basename file)))
    (match (string-rindex name #\.)
      (#f "")
      (dot (substring name (1+ dot))))))

(define (content-type file)
  (or (assoc-ref %content-types (string-downcase (extension file)))
      "application/octet-stream"))

(define (hidden? file)
  (string-prefix? "." (basename file)))

(define (directory-files directory)
  "Return the files under DIRECTORY, except hidden ones, as a sorted list of
\(path . file), PATH being the file name under DIRECTORY, such as
\"/docs/index.html\"."
  (sort (file-system-fold
         (lambda (dir stat result)         ;enter?
           (or (string=? dir directory) (not (hidden? dir))))
         (lambda (file stat result)        ;leaf
           (if (hidden? file)
               result
               (cons (cons (string-drop file (string-length directory)) file)
                     result)))
         (lambda (dir stat result) result) ;down
         (lambda (dir stat result) result) ;up
         (lambda (dir stat result) result) ;skip
         (lambda (file stat errno result)
           (error "cannot read" file (strerror errno)))
         '()
         directory)
        (lambda (a b) (string<? (car a) (car b)))))

(define (file-base64 file)
  (base64-encode (call-with-input-file file get-bytevector-all #:binary #t)))

(define (file-hash file)
  "The hash Cloudflare identifies FILE with: 32 hexadecimal digits of the
SHA-256 of its content in base64 followed by its extension."
  (string-take (bytevector->base16-string
                (sha256 (string->utf8 (string-append (file-base64 file)
                                                     (extension file)))))
               32))

(define (assets-manifest directory)
  "Return the files of DIRECTORY as a list of (path file hash)."
  (map (match-lambda
         ((path . file) (list path file (file-hash file))))
       (directory-files directory)))

(define (manifest-digest manifest)
  "A digest of MANIFEST: it changes whenever a file is added, removed or
changed."
  (bytevector->base16-string
   (sha256 (string->utf8
            (string-concatenate
             (map (match-lambda
                    ((path _ hash) (string-append path " " hash "\n")))
                  manifest))))))

;;; Publishing.

(define (account-path account . rest)
  (apply string-append "/accounts/" account rest))

(define (upload-assets account name directory)
  "Upload the files of DIRECTORY that Cloudflare does not have yet, for the
Worker NAME, and return the token to publish them with."
  (let* ((manifest (assets-manifest directory))
         (session (cloudflare-request
                   'POST (account-path account "/workers/scripts/" name
                                       "/assets-upload-session")
                   `(("manifest"
                      . ,(map (match-lambda
                                ((path file hash)
                                 `(,path ("hash" . ,hash)
                                         ("size" . ,(stat:size (stat file))))))
                              manifest)))))
         (session-token (json-ref session "jwt")))
    (define (part hash)
      (match (find (match-lambda ((_ _ h) (string=? h hash))) manifest)
        ((_ file _) (list hash hash (content-type file) (file-base64 file)))))
    ;; The files are uploaded in the buckets Cloudflare asks for; the last
    ;; upload returns the token to publish them.  When Cloudflare already
    ;; has every file, the session's token is enough.
    (fold (lambda (bucket token)
            (or (json-ref (cloudflare-upload
                           'POST (account-path account
                                               "/workers/assets/upload?base64=true")
                           (map part (vector->list bucket))
                           #:bearer session-token)
                          "jwt")
                token))
          session-token
          (vector->list (or (json-ref session "buckets") #())))))

(define (secret-value name)
  (or (getenv name)
      (error "cloudflare-worker: environment variable of secret not set" name)))

(define (publish! account props)
  "Publish the Worker of PROPS: its script, its files, and what its code
is given."
  (let* ((name (assq-ref props 'name))
         (script (assq-ref props 'script))
         (directory (assq-ref props 'directory))
         (bindings
          (append (map (match-lambda
                         ((variable . value)
                          `(("type" . "plain_text") ("name" . ,variable)
                            ("text" . ,value))))
                       (assq-ref props 'vars))
                  (map (match-lambda
                         ((secret . _)
                          `(("type" . "secret_text") ("name" . ,secret)
                            ("text" . ,(secret-value secret)))))
                       (assq-ref props 'secrets))
                  (if (and script directory)
                      '((("type" . "assets") ("name" . "ASSETS")))
                      '())
                  (assq-ref props 'bindings))))
    (cloudflare-upload
     'PUT (account-path account "/workers/scripts/" name)
     (cons (list "metadata" #f "application/json"
                 (scm->json-string
                  `(("compatibility_date" . ,%compatibility-date)
                    ,@(if script
                          `(("main_module" . ,(basename script)))
                          '())
                    ,@(if directory
                          `(("assets"
                             . (("jwt" . ,(upload-assets account name
                                                         directory)))))
                          '())
                    ("bindings" . ,(list->vector bindings)))))
           (if script
               (list (list (basename script) (basename script)
                           "application/javascript+module"
                           (call-with-input-file script get-string-all)))
               '())))))

(define (schedule! account name crons)
  "Run the Worker NAME at the times of CRONS."
  (cloudflare-request 'PUT (account-path account "/workers/scripts/" name
                                         "/schedules")
                      (list->vector (map (lambda (cron) `(("cron" . ,cron)))
                                         crons))))

;;; Domains.

(define (hostname-zone-id hostname)
  "The ID of the Cloudflare zone HOSTNAME belongs to."
  (let loop ((name hostname))
    (match (vector->list (or (cloudflare-request
                              'GET (string-append "/zones?name=" name))
                             #()))
      ((zone . _) (json-ref zone "id"))
      (()
       (match (string-index name #\.)
         (#f (error "no Cloudflare zone for" hostname))
         (dot (loop (substring name (1+ dot)))))))))

(define (attach-domain! account name hostname)
  "Serve the Worker NAME at HOSTNAME; return the ID of this domain."
  (json-ref (cloudflare-request
             'PUT (account-path account "/workers/domains")
             `(("hostname" . ,hostname)
               ("service" . ,name)
               ("zone_id" . ,(hostname-zone-id hostname))
               ("environment" . "production")))
            "id"))

(define (detach-domain! account domain-id)
  (cloudflare-delete (account-path account "/workers/domains/" domain-id)))

(define (enable-workers-dev! account name)
  "Serve the Worker NAME on its workers.dev address, and return it."
  (cloudflare-request 'POST (account-path account "/workers/scripts/" name
                                          "/subdomain")
                      '(("enabled" . #t)))
  (format #f "https://~a.~a.workers.dev/" name
          (json-ref (cloudflare-request
                     'GET (account-path account "/workers/subdomain"))
                    "subdomain")))

(define (serve! account name domain)
  "Make the Worker NAME reachable, at DOMAIN or else on workers.dev; return
the outputs about it."
  (if domain
      `((domain-id . ,(attach-domain! account name domain))
        (url . ,(string-append "https://" domain "/")))
      `((domain-id . #f)
        (url . ,(enable-workers-dev! account name)))))

;;; The provider.

(define (create-worker _ props)
  (let* ((account (account-id))
         (name (assq-ref props 'name))
         (outputs `((name . ,name) (account-id . ,account))))
    (publish! account props)
    (unless (null? (assq-ref props 'crons))
      (schedule! account name (assq-ref props 'crons)))
    (created! (append outputs '((domain-id . #f) (url . #f)))
              props '((domain . unreachable)))
    (append outputs (serve! account name (assq-ref props 'domain)))))

(define (read-worker outputs)
  (and (cloudflare-get (account-path (assq-ref outputs 'account-id)
                                     "/workers/scripts/"
                                     (assq-ref outputs 'name) "/settings"))
       (cons '() outputs)))

(define (update-worker outputs old new)
  (define (changed? key)
    (not (equal? (assq-ref old key) (assq-ref new key))))
  (let ((account (assq-ref outputs 'account-id))
        (name (assq-ref outputs 'name)))
    (when (any changed? '(assets directory script script-hash vars secrets
                          bindings))
      (publish! account new))
    (when (changed? 'crons)
      (schedule! account name (assq-ref new 'crons)))
    (if (changed? 'domain)
        (begin
          (and=> (assq-ref outputs 'domain-id)
                 (lambda (id) (detach-domain! account id)))
          (append `((name . ,name) (account-id . ,account))
                  (serve! account name (assq-ref new 'domain))))
        outputs)))

(define (delete-worker outputs)
  (let ((account (assq-ref outputs 'account-id)))
    (and=> (assq-ref outputs 'domain-id)
           (lambda (id) (detach-domain! account id)))
    (cloudflare-delete (account-path account "/workers/scripts/"
                                     (assq-ref outputs 'name) "?force=true"))))

(define worker-provider
  (register-provider!
   (make-provider 'cloudflare-worker
                  #:create create-worker
                  #:read read-worker
                  #:update update-worker
                  #:delete delete-worker
                  #:replace-on '(name))))

(define (kv-binding variable namespace)
  "Give the code, as VARIABLE, the KV NAMESPACE."
  `(("type" . "kv_namespace") ("name" . ,variable) ("namespace_id" . ,namespace)))

(define (d1-binding variable database)
  "Give the code, as VARIABLE, the D1 DATABASE."
  `(("type" . "d1") ("name" . ,variable) ("id" . ,database)))

(define (file-digest file)
  (bytevector->base16-string
   (sha256 (call-with-input-file file get-bytevector-all #:binary #t))))

(define* (cloudflare-worker resource-name
                            #:key script assets domain (vars '()) (secrets '())
                            (crons '()) (bindings '()) name)
  "Declare a Worker running SCRIPT, a JavaScript module, and serving the
files of ASSETS, a directory; it needs one or both.  It is served at
DOMAIN, a host name in a zone managed by Cloudflare, or else on its
workers.dev address.  VARS, an association list of strings, and SECRETS, a
list of names of environment variables, are given to the code, along with
BINDINGS, made with `kv-binding' and `d1-binding'.  CRONS are the times to
run its scheduled handler, such as \"*/30 * * * *\".  It is published again
whenever a file, or any of these, changes."
  (unless (or script assets)
    (error "cloudflare-worker: #:script or #:assets is required" resource-name))
  (when (and assets (not (file-is-directory? assets)))
    (error "cloudflare-worker: not a directory" assets))
  (let ((directory (and assets (string-trim-right assets #\/))))
    (ensure-resource worker-provider resource-name
                     `((name . ,(or name
                                    (match (current-stage)
                                      (#f resource-name)
                                      (stage (string-append
                                              resource-name "-"
                                              (stage-name stage))))))
                       (script . ,script)
                       (script-hash . ,(and script (file-digest script)))
                       (directory . ,directory)
                       (assets . ,(and directory
                                       (manifest-digest
                                        (assets-manifest directory))))
                       (vars . ,(sort vars (lambda (a b)
                                             (string<? (car a) (car b)))))
                       ;; Only a digest of each value: secrets are not saved.
                       (secrets . ,(map (lambda (secret)
                                          (cons secret
                                                (bytevector->base16-string
                                                 (sha256 (string->utf8
                                                          (secret-value secret))))))
                                        (sort secrets string<?)))
                       (bindings . ,bindings)
                       (crons . ,crons)
                       (domain . ,domain)))))
