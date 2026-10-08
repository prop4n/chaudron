;; A server reachable over SSH.
;;
;;   HCLOUD_TOKEN=... guile -L . examples/forge.scm
;;   HCLOUD_TOKEN=... guile -L . examples/forge.scm destroy

(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match)
             (ice-9 textual-ports))

(define (read-file file)
  (call-with-input-file file get-string-all))

(match (command-line)
  ((_ "destroy")
   (destroy-stage "prod"))
  (_
   (with-stage "prod"
     (let* ((key (hetzner-ssh-key "moi"
                                  #:public-key (read-file
                                                (string-append
                                                 (getenv "HOME")
                                                 "/.ssh/id_ed25519.pub"))))
            (forge (hetzner-server "forge"
                                   #:type "cx22"
                                   #:location "fsn1"
                                   #:ssh-keys (list key))))
       (format #t "ssh root@~a~%" (output forge 'ipv4))))))
