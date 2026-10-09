(use-modules (gnu)
             (gnu machine hetzner))

(operating-system
  (inherit (make-hetzner-os (getenv "CHAUDRON_SERVER_TYPE")))
  (host-name "forge")
  (timezone "Europe/Paris")
  (packages (append (specifications->packages '("git" "htop" "fastfetch"))
                    %base-packages)))
