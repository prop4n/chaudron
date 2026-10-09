;; Tests for Guix System on Hetzner servers, against a fake API and fake
;; commands: nothing is installed nor deployed for real.

(use-modules (chaudron)
             (chaudron command)
             (chaudron hetzner)
             (chaudron resource)
             (ice-9 match)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-26)
             (srfi srfi-64)
             (tests fake-hetzner))

;;; Fake commands.

(define commands '())                   ;what was run, summarized
(define results '())                    ;(status . output), consumed in order
(define script #f)                      ;the last script fed to a command
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
  (when input (set! script input))
  (match results
    (((status . output) . rest)
     (set! results rest)
     (values status output))
    (() (error "unexpected command" program arguments))))

(define-syntax-rule (with-commands (result ...) api-responses body ...)
  (begin
    (set! commands '())
    (set! results (list result ...))
    (parameterize ((run-command fake-run))
      (call-with-api api-responses (lambda () body ...)))))

;;; The infrastructure.

(define os-file
  (let* ((port (mkstemp "/tmp/chaudron-os-XXXXXX"))
         (file (port-filename port)))
    (display "(operating-system ...)" port)
    (close-port port)
    file))

(define* (forge #:key (type "cx23"))
  (make-resource 'hetzner-server "forge" `((type . ,type))
                 '((id . 42) (ipv4 . "1.2.3.4"))))

(define* (guix-system #:key (server (forge)) dry-run?)
  (quietly
   (lambda ()
     (with-stage "guix" #:dry-run? dry-run?
       (hetzner-guix-system "forge" #:server server #:os os-file
                            #:ssh-key 7 #:identity "/keys/id")))))

(define describe '(0 . "(list (channel (name 'guix) (commit \"abc\")))"))
(define (hashed value) `(0 . ,(string-append value "\n")))
(define ok '(0 . #f))
(define not-guix '(1 . #f))

;; Recent OpenSSH prints a comment before the keys.
(define keyscan
  '(0 . "# 1.2.3.4:22 SSH-2.0-OpenSSH_10.2\n1.2.3.4 ssh-ed25519 AAAAKEY\n"))

(test-begin "hetzner-guix")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "installs Guix System, then deploys"
    '((("guix" "describe") ("guix" "hash")
       ("ssh" "test -e /run/current-system")
       ("ssh" "true") ("ssh" "true") ("ssh" "bash" "-s")
       ("ssh" "test -e /run/current-system")
       ("ssh-keyscan" "-t") ("guix" "deploy"))
      ((POST "/servers/42/actions/enable_rescue")
       (POST "/servers/42/actions/reset")
       (POST "/servers/42/actions/reboot")))
    (with-commands (describe (hashed "h1") not-guix
                    '(255 . #f) ok ok ok   ;not up yet, then up
                    keyscan ok)
                   (list (done 1) (done 2) (done 3))
      (guix-system)
      (list commands (routes))))

  (test-equal "enables the rescue system with the SSH key"
    #(7)
    (assoc-ref (body 0) "ssh_keys"))

  (test-assert "erases the disk and installs a BIOS system for cx types"
    (and (string-contains script "mkfs.ext4 -q -F /dev/sda1")
         (string-contains script "guix system init /tmp/bootstrap.scm /mnt")
         (string-contains script "grub-bootloader")
         (not (string-contains script "/dev/sda15"))))

  (test-assert "deploys to the server with its host key"
    (and (string-contains deployment "managed-host-environment-type")
         (string-contains deployment "\"1.2.3.4\"")
         (string-contains deployment "\"ssh-ed25519 AAAAKEY\"")
         (string-contains deployment "\"x86_64-linux\"")
         (string-contains deployment os-file)
         ;; Or activating the system would forget our signing key.
         (string-contains deployment "/etc/guix/signing-key.pub")))

  (test-equal "does nothing when neither the configuration nor Guix changed"
    '(("guix" "describe") ("guix" "hash"))
    (with-commands (describe (hashed "h1")) '()
      (guix-system)
      commands))

  (test-equal "deploys again when they changed"
    '(("guix" "describe") ("guix" "hash") ("guix" "deploy"))
    (with-commands (describe (hashed "h2") ok) '()
      (guix-system)
      commands))

  (test-equal "only says it would deploy during a dry run"
    '(("guix" "describe") ("guix" "hash"))
    (with-commands (describe (hashed "h3")) '()
      (guix-system #:dry-run? #t)
      commands))

  (test-assert "installs an EFI system for other types"
    (with-commands (describe (hashed "h3") not-guix ok ok ok keyscan ok)
                   (list (done 1) (done 2) (done 3))
      (guix-system #:server (make-resource 'hetzner-server "forge"
                                           '((type . "cpx22"))
                                           '((id . 43) (ipv4 . "1.2.3.4"))))
      (and (string-contains script "grub-efi-bootloader")
           (string-contains script "mount /dev/sda15 /mnt/boot/efi")))))

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))
  (test-equal "does not install Guix System again if it already runs"
    '(("guix" "describe") ("guix" "hash")
      ("ssh" "test -e /run/current-system")
      ("ssh-keyscan" "-t") ("guix" "deploy"))
    (with-commands (describe (hashed "h1") ok keyscan ok) '()
      (guix-system)
      commands)))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "hetzner-guix")
(exit (zero? failures))
