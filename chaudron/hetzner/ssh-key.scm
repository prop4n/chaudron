;;; Hetzner Cloud SSH keys.

(define-module (chaudron hetzner ssh-key)
  #:use-module (chaudron command)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:use-module (ice-9 textual-ports)
  #:export (hetzner-ssh-key))

(define (ssh-key-outputs key)
  `((id . ,(json-ref key "id"))
    (fingerprint . ,(json-ref key "fingerprint"))))

(define (create-ssh-key _ props)
  (ssh-key-outputs
   (json-ref (hetzner-request 'POST "/ssh_keys"
                              `(("name" . ,(assq-ref props 'name))
                                ("public_key" . ,(assq-ref props 'public-key))
                                ("labels" . ,(labels->json props))))
             "ssh_key")))

(define (read-ssh-key outputs)
  (and=> (json-ref (hetzner-get (resource-path "ssh_keys" (assq-ref outputs 'id)))
                   "ssh_key")
         (lambda (key)
           (cons (observe-metadata key) (ssh-key-outputs key)))))

(define (update-ssh-key outputs old new)
  (update-metadata! "ssh_keys" (assq-ref outputs 'id) old new)
  outputs)

(define (delete-ssh-key outputs)
  (hetzner-delete (resource-path "ssh_keys" (assq-ref outputs 'id))))

(define ssh-key-provider
  (register-provider!
   (make-provider 'hetzner-ssh-key
                  #:create create-ssh-key
                  #:read read-ssh-key
                  #:update update-ssh-key
                  #:delete delete-ssh-key
                  #:replace-on '(public-key))))

(define* (hetzner-ssh-key resource-name
                          #:key public-key public-key-file (labels '())
                          (name resource-name))
  "Declare an SSH key, given as a string with PUBLIC-KEY or read from
PUBLIC-KEY-FILE, such as \"~/.ssh/id_ed25519.pub\".  Changing the key
replaces it."
  (let ((key (cond (public-key public-key)
                   (public-key-file
                    (call-with-input-file (expand-home public-key-file)
                      get-string-all))
                   (else
                    (error "hetzner-ssh-key: missing #:public-key or \
#:public-key-file" resource-name)))))
    (ensure-resource ssh-key-provider resource-name
                     `((name . ,name)
                       (public-key . ,(string-trim-both key))
                       (labels . ,(sorted-labels labels))))))
