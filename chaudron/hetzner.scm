;;; Hetzner Cloud resources.

(define-module (chaudron hetzner)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner firewall)
  #:use-module (chaudron hetzner load-balancer)
  #:use-module (chaudron hetzner network)
  #:use-module (chaudron hetzner primary-ip)
  #:use-module (chaudron hetzner server)
  #:use-module (chaudron hetzner snapshot)
  #:use-module (chaudron hetzner ssh-key)
  #:use-module (chaudron hetzner volume)
  #:re-export (hetzner-ssh-key
               hetzner-firewall
               allow-in
               hetzner-server
               hetzner-volume
               hetzner-primary-ip
               hetzner-network
               hetzner-load-balancer
               forward
               hetzner-snapshot
               hetzner-token
               hetzner-error?
               hetzner-error-status
               hetzner-error-code)
  #:export (with-hetzner))

(define-syntax-rule (with-hetzner token body ...)
  "Evaluate BODY using TOKEN to authenticate against Hetzner Cloud."
  (parameterize ((hetzner-token token))
    body ...))
