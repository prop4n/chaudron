;;; Installing Guix System on a Hetzner server from its rescue system.

(define-module (chaudron hetzner guix-bootstrap)
  #:use-module (chaudron command)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:use-module (ice-9 pretty-print)
  #:use-module (ice-9 receive)
  #:export (bootstrap-guix-system!
            arm?))

(define (ssh-arguments identity address . command)
  `("-i" ,identity
    ;; Host keys change when the rescue system and Guix System boot.
    "-o" "StrictHostKeyChecking=no" "-o" "UserKnownHostsFile=/dev/null"
    "-o" "LogLevel=ERROR" "-o" "ConnectTimeout=10"
    ,(string-append "root@" address) ,@command))

(define* (wait-for-ssh identity address #:optional (test "true"))
  "Wait until TEST, a shell command, succeeds over SSH on ADDRESS."
  (let loop ((tries 0))
    (receive (status _) ((run-command) "ssh"
                         (ssh-arguments identity address test))
      (unless (eqv? 0 status)
        (when (>= tries 60)
          (error "could not connect over SSH" address))
        ((hetzner-sleep) 5)
        (loop (1+ tries))))))

(define (efi? server-type)
  (not (or (string-prefix-ci? "cx" server-type)
           (and (string-prefix-ci? "cpx" server-type)
                (string-suffix? "1" server-type)))))

(define (arm? server-type)
  (string-prefix-ci? "cax" server-type))

(define (bootstrap-operating-system host-name server-type)
  "Return a minimal operating system declaration for SERVER-TYPE: just
enough to be reached over SSH and deployed to."
  (let ((efi? (efi? server-type)))
    `(operating-system
       (host-name ,host-name)
       (bootloader (bootloader-configuration
                    (bootloader ,(if efi? 'grub-efi-bootloader 'grub-bootloader))
                    (targets (list ,(if efi? "/boot/efi" "/dev/sda")))
                    (terminal-outputs '(console))))
       (initrd-modules (append (list ,@(if (arm? server-type)
                                           '("sd_mod" "virtio_scsi")
                                           '("virtio_scsi")))
                               %base-initrd-modules))
       (file-systems (cons* (file-system
                              (mount-point "/")
                              (device "/dev/sda1")
                              (type "ext4"))
                            ,@(if efi?
                                  '((file-system
                                      (mount-point "/boot/efi")
                                      (device "/dev/sda15")
                                      (type "vfat")))
                                  '())
                            %base-file-systems))
       (services (cons* (service dhcpcd-service-type)
                        (service openssh-service-type
                                 (openssh-configuration
                                  (openssh openssh-sans-x)
                                  (permit-root-login 'prohibit-password)))
                        %base-services)))))

(define (bootstrap-script host-name server-type)
  "Return a script that, run on the rescue system, erases the disk and
installs a minimal Guix System on it."
  (string-append "set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -q -y cloud-guest-utils uidmap
growpart /dev/sda 1 || true
mkfs.ext4 -q -F /dev/sda1
mount /dev/sda1 /mnt
" (if (efi? server-type)
      "mkdir -p /mnt/boot/efi
mount /dev/sda15 /mnt/boot/efi
"
      "") "mkdir -p -m 700 /mnt/root/.ssh
cp /root/.ssh/authorized_keys /mnt/root/.ssh/
# The rescue system is small: keep the store on the target disk.
mkdir -p /mnt/tmp/gnu /gnu
mount --bind /mnt/tmp/gnu /gnu
wget -q -O /tmp/guix-install.sh https://guix.gnu.org/guix-install.sh
chmod +x /tmp/guix-install.sh
set +o pipefail
yes '' | /tmp/guix-install.sh
set -o pipefail
cat > /tmp/bootstrap.scm <<'EOF'
(use-modules (gnu))
(use-service-modules networking ssh)
(use-package-modules ssh)
" (with-output-to-string
    (lambda ()
      (pretty-print (bootstrap-operating-system host-name server-type))))
"EOF
guix system init /tmp/bootstrap.scm /mnt
"))

(define (bootstrap-guix-system! props)
  "Erase the disk of the server of PROPS and install a minimal Guix System\non it, reachable over SSH as root."
  (let ((server (assq-ref props 'server))
        (address (assq-ref props 'address))
        (identity (assq-ref props 'identity)))
    (report "~a: erasing its disk to install Guix System" address)
    (resource-action "servers" server "enable_rescue"
                     `(("type" . "linux64")
                       ("ssh_keys" . ,(vector (assq-ref props 'ssh-key)))))
    (resource-action "servers" server "reset")
    (wait-for-ssh identity address)
    (invoke "ssh" (ssh-arguments identity address "bash" "-s")
            #:input (bootstrap-script (assq-ref props 'host-name)
                                      (assq-ref props 'server-type)))
    (resource-action "servers" server "reboot")
    ;; Until it has rebooted, the rescue system may still answer.
    (wait-for-ssh identity address "test -e /run/current-system")))
