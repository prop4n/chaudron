;; Tests for Guix System on Oracle Cloud instances, with fake commands:
;; nothing is deployed for real.

(use-modules (chaudron)
             (chaudron command)
             (chaudron oracle)
             (chaudron resource)
             (ice-9 match)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-26)
             (srfi srfi-64)
             (tests fake-api))

;;; Fake commands.

(define commands '())                   ;what was run, summarized
(define results '())                    ;(status . output), consumed in order
(define deployment #f)                  ;the last file given to 'guix deploy'

(define (summary program arguments)
  (match (cons program arguments)
    (("ssh" . arguments)                ;keep the remote command only
     (cons "ssh" (cdr (find-tail (cut string-prefix? "root@" <>) arguments))))
    (("guix" "deploy" file)
     (set! deployment (call-with-input-file file get-string-all))
     '("guix" "deploy"))
    ((program first . _) (list program first))))

(define* (fake-run program arguments #:key input capture?)
  (set! commands (append commands (list (summary program arguments))))
  (match results
    (((status . output) . rest)
     (set! results rest)
     (values status output))
    (() (error "unexpected command" program arguments))))

(define-syntax-rule (with-commands (result ...) body ...)
  (begin
    (set! commands '())
    (set! results (list result ...))
    (parameterize ((run-command fake-run))
      (call-with-api '() (lambda () body ...)))))

;;; The infrastructure.

(define os-file
  (let* ((port (mkstemp "/tmp/chaudron-os-XXXXXX"))
         (file (port-filename port)))
    (display "(operating-system ...)" port)
    (close-port port)
    file))

(define* (instance #:key (shape "VM.Standard.A1.Flex"))
  (make-resource 'oracle-instance "web" `((shape . ,shape))
                 '((id . "i1") (ipv4 . "1.2.3.4"))))

(define* (guix-system #:key (shape "VM.Standard.A1.Flex"))
  (quietly
   (lambda ()
     (with-stage "guix"
       (oracle-guix-system "web" #:instance (instance #:shape shape)
                           #:os os-file #:identity "/keys/id")))))

(define derivation '(0 . "/gnu/store/abc-system.drv\n"))
(define describe '(0 . "(list (channel (name 'guix) (commit \"abc\")))"))
(define (hashed value) `(0 . ,(string-append value "\n")))
(define ok '(0 . #f))
(define keyscan '(0 . "1.2.3.4 ssh-ed25519 AAAAKEY\n"))

(test-begin "oracle-guix")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "waits for the instance to run Guix System, then deploys"
    '(("guix" "system") ("guix" "describe") ("guix" "hash")
      ("ssh" "test -e /run/current-system")
      ("ssh" "test -e /run/current-system")
      ("ssh-keyscan" "-t") ("guix" "deploy"))
    (with-commands (derivation describe (hashed "h1") '(255 . #f) ok keyscan ok)
      (guix-system)
      commands))

  (test-assert "deploys an Arm system to Arm shapes, with the host key"
    (and (string-contains deployment "\"1.2.3.4\"")
         (string-contains deployment "\"ssh-ed25519 AAAAKEY\"")
         (string-contains deployment "\"aarch64-linux\"")
         (string-contains deployment os-file)
         (string-contains deployment "/etc/guix/signing-key.pub")
         ;; The instance builds the system itself.
         (string-contains deployment "(build-locally? #f)")))

  (test-equal "does nothing when neither the configuration nor Guix changed"
    '(("guix" "system") ("guix" "describe") ("guix" "hash"))
    (with-commands (derivation describe (hashed "h1"))
      (guix-system)
      commands))

  (test-equal "deploys again when they changed"
    '(("guix" "system") ("guix" "describe") ("guix" "hash")
      ("ssh" "test -e /run/current-system")
      ("guix" "deploy"))
    (with-commands (derivation describe (hashed "h2") ok ok)
      (guix-system)
      commands)))

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))
  (test-assert "deploys an x86 system to other shapes"
    (with-commands (derivation describe (hashed "h1") ok keyscan ok)
      (guix-system #:shape "VM.Standard.E2.1.Micro")
      (string-contains deployment "\"x86_64-linux\""))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "oracle-guix")
(exit (zero? failures))
