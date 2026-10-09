;;; Guix System on Hetzner servers: install it once from the rescue system,
;;; then deploy configurations with 'guix deploy'.

(define-module (chaudron hetzner guix-system)
  #:use-module (chaudron command)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner guix-bootstrap)
  #:use-module (ice-9 match)
  #:use-module (ice-9 pretty-print)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:export (hetzner-guix-system))

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

(define (deploy! props outputs)
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
                (host-key ,(assq-ref outputs 'host-key))))))
      port)
     (close-port port)
     (invoke "guix" (list "deploy" file))))
  outputs)

(define (create-guix-system _ props)
  (unless (guix-system-running? (assq-ref props 'identity)
                                (assq-ref props 'address))
    (bootstrap-guix-system! props))
  (deploy! props
           `((host-key . ,(host-key (assq-ref props 'address)))
             (system . ,(if (arm? (assq-ref props 'server-type))
                            "aarch64-linux"
                            "x86_64-linux")))))

(define (update-guix-system outputs old new)
  ;; The server may have just been resized, and still be booting.
  (wait-for-guix-system (assq-ref new 'identity) (assq-ref new 'address))
  (deploy! new outputs))

(define guix-system-provider
  (register-provider!
   (make-provider 'hetzner-guix-system
                  #:create create-guix-system
                  #:update update-guix-system
                  ;; Stop managing it; the server itself is left as is.
                  #:delete (const #t)
                  #:replace-on '(server))))

;;; Declaring.

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

(define* (hetzner-guix-system resource-name
                              #:key server os ssh-key
                              (identity "~/.ssh/id_ed25519"))
  "Run Guix System on SERVER, a `hetzner-server', configured by OS, a file
whose last expression is an operating system, typically based on
`make-hetzner-os' from (gnu machine hetzner).  SSH-KEY is the
`hetzner-ssh-key' of IDENTITY, the private key used to reach the server.

The first time, the server's disk is erased to install Guix System.  Then
OS is deployed with 'guix deploy' whenever it, or the Guix in use, changes."
  (unless (and server os ssh-key)
    (error "hetzner-guix-system: #:server, #:os and #:ssh-key are required"
           resource-name))
  (let ((os (canonicalize-path os)))
    (ensure-resource guix-system-provider resource-name
                     `((server . ,server)
                       (address . ,(output server 'ipv4))
                       (server-type . ,(assq-ref (resource-props server) 'type))
                       (host-name . ,resource-name)
                       (ssh-key . ,ssh-key)
                       (identity . ,(expand-home identity))
                       (os . ,os)
                       (configuration . ,(configuration-hash os))))))
