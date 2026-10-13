;;; Guix System on Oracle Cloud instances started from a Guix System image:
;;; deploy configurations to them with 'guix deploy'.

(define-module (chaudron oracle guix-system)
  #:use-module (chaudron command)
  #:use-module (chaudron guix-deploy)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle api)
  #:use-module (ice-9 receive)
  #:export (oracle-guix-system))

(define (wait-for-guix-system identity address)
  "Wait until ADDRESS runs Guix System and answers over SSH, as after it
was started or restarted."
  (report "~a: waiting for SSH" address)
  (let loop ((tries 0))
    (receive (status _) ((run-command) "ssh"
                         (ssh-arguments identity address
                                        "test -e /run/current-system"))
      (unless (eqv? 0 status)
        (when (>= tries 60)
          (error "could not reach Guix System over SSH" address))
        ((oracle-sleep) 5)
        (loop (1+ tries))))))

(define (create-guix-system _ props)
  (let ((props (resolve-files props)))
    (wait-for-guix-system (assq-ref props 'identity) (assq-ref props 'address))
    (deploy! props
             `((host-key . ,(host-key (assq-ref props 'address)))
               (system . ,(assq-ref props 'system))))))

(define (update-guix-system outputs old new)
  (let ((new (resolve-files new)))
    ;; The instance may have just been restarted, for a new shape.
    (wait-for-guix-system (assq-ref new 'identity) (assq-ref new 'address))
    (deploy! new outputs)))

(define guix-system-provider
  (register-provider!
   (make-provider 'oracle-guix-system
                  #:create create-guix-system
                  #:update update-guix-system
                  ;; Stop managing it; the instance itself is left as is.
                  #:delete (const #t)
                  #:replace-on '(instance))))

(define* (oracle-guix-system resource-name
                             #:key instance os (identity "~/.ssh/id_ed25519")
                             build-locally?)
  "Deploy OS, a file whose last expression is an operating system, to
INSTANCE, an `oracle-instance' started from a Guix System image that lets
IDENTITY, a private SSH key, in as root, and trusts this machine's Guix
signing key.  OS is deployed whenever it, or the Guix in use, changes.
The instance builds it, unless BUILD-LOCALLY?: sending a whole system from
here takes long over a slow connection."
  (unless (and instance os)
    (error "oracle-guix-system: #:instance and #:os are required"
           resource-name))
  (ensure-resource guix-system-provider resource-name
                   `((instance . ,instance)
                     (address . ,(output instance 'ipv4))
                     (system . ,(if (string-prefix?
                                     "VM.Standard.A"
                                     (assq-ref (resource-props instance)
                                               'shape))
                                    "aarch64-linux"
                                    "x86_64-linux"))
                     (identity . ,identity)
                     (build-locally? . ,(and build-locally? #t))
                     (os . ,os)
                     (configuration . ,(configuration-hash os)))))
