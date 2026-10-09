(use-modules (gnu)
             (gnu machine hetzner))

(operating-system
  (inherit (make-hetzner-os "cx33"))
  (host-name "forge")
  (timezone "Europe/Paris")
  (packages (append (specifications->packages '("git" "htop" "fastfetch"))
                    %base-packages)))
