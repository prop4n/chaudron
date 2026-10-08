;; The Guix System configuration of forge, deployed by examples/guix-forge.scm.
;; The last expression is the operating system.

(use-modules (gnu)
             (gnu machine hetzner))

(operating-system
  ;; Hetzner's bootloader, disks and SSH access for this server type.
  (inherit (make-hetzner-os "cx23"))
  (host-name "forge")
  (timezone "Europe/Paris")
  (packages (append (specifications->packages '("git" "htop"))
                    %base-packages)))
