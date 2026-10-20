;;; Deploying Guix System to machines over SSH with 'guix deploy', whatever
;;; the provider that made them.

(define-module (chaudron guix-deploy)
  #:use-module (chaudron command)
  #:use-module (chaudron stage)
  #:use-module (gcrypt base16)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 match)
  #:use-module (ice-9 pretty-print)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:export (ssh-arguments
            host-key
            deploy!
            resolve-files
            configuration-hash
            secrets-prop))

(define (ssh-arguments identity address . command)
  `("-i" ,identity
    ;; Host keys change when a machine is reinstalled or replaced.
    "-o" "StrictHostKeyChecking=no" "-o" "UserKnownHostsFile=/dev/null"
    "-o" "LogLevel=ERROR" "-o" "ConnectTimeout=10"
    ;; Fail rather than ask for a password.
    "-o" "BatchMode=yes"
    ,(string-append "root@" address) ,@command))

(define (host-key address)
  "Return the ed25519 SSH host key of ADDRESS, as 'guix deploy' wants it."
  (define (line->key line)
    ;; Lines look like "ADDRESS ssh-ed25519 KEY"; others are comments.
    (match (string-tokenize line)
      ((_ type key) (and (string-prefix? "ssh-" type)
                         (string-append type " " key)))
      (_ #f)))

  (or (any line->key
           (string-split (invoke "ssh-keyscan" (list "-t" "ed25519" address)
                                 #:capture? #t)
                         #\newline))
      (error "no SSH host key for" address)))

(define %authorize
  ;; Activating a system rewrites the keys its Guix daemon trusts: add ours,
  ;; or the next deployment would be refused.
  '(define (authorize os)
     (operating-system
       (inherit os)
       (services
        (modify-services (operating-system-user-services os)
          (guix-service-type
           config => (guix-configuration
                      (inherit config)
                      (authorized-keys
                       (cons (local-file "/etc/guix/signing-key.pub")
                             (guix-configuration-authorized-keys
                              config))))))))))

(define (shell-quote string)
  (string-append "'" (string-join (string-split string #\') "'\\''") "'"))

(define (copy-secrets! props)
  "Copy the secrets of PROPS to the machine, readable by root only."
  (for-each (match-lambda
              ((target source _)
               (let ((new (shell-quote (string-append target ".new")))
                     (target* (shell-quote target)))
                 (report "~a: copying ~a" (assq-ref props 'address) target)
                 (invoke "ssh"
                         (ssh-arguments
                          (assq-ref props 'identity) (assq-ref props 'address)
                          (format #f "umask 077 && mkdir -p ~a && cat > ~a \
&& chmod 600 ~a && mv ~a ~a"
                                  (shell-quote (dirname target))
                                  new new new target*))
                         #:input (call-with-input-file source
                                   get-string-all)))))
            (or (assq-ref props 'secrets) '())))

(define (deploy! props outputs)
  ;; Before activating the system, so that its services find them.
  (copy-secrets! props)
  (report "~a: deploying ~a" (assq-ref props 'address) (assq-ref props 'os))
  (call-with-temporary-file
   (lambda (file port)
     (pretty-print '(use-modules (gnu) (gnu machine) (gnu machine ssh)
                                 (guix gexp))
                   port)
     (pretty-print %authorize port)
     (pretty-print
      `(list (machine
              (operating-system (authorize (load ,(assq-ref props 'os))))
              (environment managed-host-environment-type)
              (configuration
               (machine-ssh-configuration
                (host-name ,(assq-ref props 'address))
                (system ,(assq-ref outputs 'system))
                (user "root")
                (identity ,(assq-ref props 'identity))
                (host-key ,(assq-ref outputs 'host-key))
                ;; Building on the machine spares sending it the system.
                ,@(if (assq 'build-locally? props)
                      `((build-locally? ,(assq-ref props 'build-locally?)))
                      '())))))
      port)
     (close-port port)
     (invoke "guix" (list "deploy" file))))
  outputs)

(define (resolve-files props)
  "Return PROPS with their files as found from where chaudron runs: the state
keeps them as written, so that it fits any machine."
  (map (match-lambda
         (('os . file) (cons 'os (canonicalize-path file)))
         (('identity . file) (cons 'identity (expand-home file)))
         (('secrets . secrets)
          (cons 'secrets
                (map (match-lambda
                       ((target source digest)
                        (list target (canonicalize-path (expand-home source))
                              digest)))
                     secrets)))
         (prop prop))
       props))

(define (configuration-hash os-file)
  "Return a hash of OS-FILE and of the Guix in use: deploying again is needed
when either changes."
  (call-with-temporary-file
   (lambda (file port)
     (display (call-with-input-file os-file get-string-all) port)
     (display (invoke "guix" '("describe" "--format=channels") #:capture? #t)
              port)
     (close-port port)
     (string-trim-both (invoke "guix" (list "hash" file) #:capture? #t)))))

(define (secrets-prop secrets)
  "Return the props of SECRETS, an alist of files on the machine and the
local files they are copied from: their names and a digest of their
contents, never the contents.  None without secrets."
  (if (null? secrets)
      '()
      `((secrets
         . ,(map (match-lambda
                   ((target . source)
                    (list target source
                          (bytevector->base16-string
                           (file-sha256 (expand-home source))))))
                 (sort secrets (lambda (a b) (string<? (car a) (car b)))))))))
