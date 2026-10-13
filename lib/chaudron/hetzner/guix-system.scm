;;; Guix System on Hetzner servers: install it once from the rescue system,
;;; then deploy configurations with 'guix deploy'.

(define-module (chaudron hetzner guix-system)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron guix-deploy)
  #:use-module (chaudron hetzner guix-bootstrap)
  #:export (hetzner-guix-system))

(define (create-guix-system _ props)
  (let ((props (resolve-files props)))
    (unless (guix-system-running? (assq-ref props 'identity)
                                  (assq-ref props 'address))
      (bootstrap-guix-system! props))
    (deploy! props
             `((host-key . ,(host-key (assq-ref props 'address)))
               (system . ,(if (arm? (assq-ref props 'server-type))
                              "aarch64-linux"
                              "x86_64-linux"))))))

(define (update-guix-system outputs old new)
  (let ((new (resolve-files new)))
    ;; The server may have just been resized, and still be booting.
    (wait-for-guix-system (assq-ref new 'identity) (assq-ref new 'address))
    (deploy! new outputs)))

(define guix-system-provider
  (register-provider!
   (make-provider 'hetzner-guix-system
                  #:create create-guix-system
                  #:update update-guix-system
                  ;; Stop managing it; the server itself is left as is.
                  #:delete (const #t)
                  #:replace-on '(server))))

;;; Declaring.

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
  (ensure-resource guix-system-provider resource-name
                   `((server . ,server)
                     (address . ,(output server 'ipv4))
                     (server-type . ,(assq-ref (resource-props server) 'type))
                     (host-name . ,resource-name)
                     (ssh-key . ,ssh-key)
                     (identity . ,identity)
                     (os . ,os)
                     (configuration . ,(configuration-hash os)))))
