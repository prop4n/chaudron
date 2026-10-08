;;; Hetzner Cloud resources.

(define-module (chaudron hetzner)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:re-export (hetzner-token
               hetzner-error?
               hetzner-error-status
               hetzner-error-code)
  #:export (with-hetzner
            hetzner-ssh-key
            hetzner-server))

(define-syntax-rule (with-hetzner token body ...)
  "Evaluate BODY using TOKEN to authenticate against Hetzner Cloud."
  (parameterize ((hetzner-token token))
    body ...))

(define (labels)
  `(("chaudron/stage" . ,(stage-name (current-stage)))))

(define (changed? key old new)
  (not (equal? (assq-ref old key) (assq-ref new key))))

;;; SSH keys.

(define (create-ssh-key _ props)
  (let ((key (json-ref (hetzner-request
                        'POST "/ssh_keys"
                        `(("name" . ,(assq-ref props 'name))
                          ("public_key" . ,(assq-ref props 'public-key))
                          ("labels" . ,(labels))))
                       "ssh_key")))
    `((id . ,(json-ref key "id"))
      (fingerprint . ,(json-ref key "fingerprint")))))

(define (delete-ssh-key outputs)
  (hetzner-delete (format #f "/ssh_keys/~a" (assq-ref outputs 'id))))

(define ssh-key-provider
  (register-provider!
   (make-provider 'hetzner-ssh-key
                  #:create create-ssh-key
                  #:delete delete-ssh-key)))

(define* (hetzner-ssh-key resource-name #:key public-key (name resource-name))
  "Declare an SSH key.  Any change replaces it."
  (unless public-key
    (error "hetzner-ssh-key: missing #:public-key" resource-name))
  (ensure-resource ssh-key-provider resource-name
                   `((name . ,name)
                     (public-key . ,(string-trim-both public-key)))))

;;; Servers.

(define (server-path outputs . rest)
  (apply string-append "/servers/" (number->string (assq-ref outputs 'id))
         rest))

(define* (server-action outputs action #:optional body)
  (wait-for-action
   (json-ref (hetzner-request 'POST (server-path outputs "/actions/" action)
                              body)
             "action")))

(define (create-server _ props)
  (let ((response (hetzner-request
                   'POST "/servers"
                   `(("name" . ,(assq-ref props 'name))
                     ("server_type" . ,(assq-ref props 'type))
                     ("location" . ,(assq-ref props 'location))
                     ("image" . ,(assq-ref props 'image))
                     ("ssh_keys" . ,(list->vector (assq-ref props 'ssh-keys)))
                     ("labels" . ,(labels))))))
    (wait-for-action (json-ref response "action"))
    (for-each wait-for-action
              (vector->list (or (json-ref response "next_actions") #())))
    (let ((server (json-ref response "server")))
      `((id . ,(json-ref server "id"))
        (ipv4 . ,(json-ref server "public_net" "ipv4" "ip"))
        (ipv6 . ,(json-ref server "public_net" "ipv6" "ip"))))))

(define (update-server outputs old new)
  (when (changed? 'name old new)
    (hetzner-request 'PUT (server-path outputs)
                     `(("name" . ,(assq-ref new 'name)))))
  (when (changed? 'type old new)
    ;; Resizing requires the server to be off.  The disk is left as is, so
    ;; that the server can be downgraded again later.
    (server-action outputs "poweroff")
    (server-action outputs "change_type"
                   `(("server_type" . ,(assq-ref new 'type))
                     ("upgrade_disk" . #f)))
    (server-action outputs "poweron"))
  outputs)

(define (delete-server outputs)
  (and=> (hetzner-delete (server-path outputs))
         (lambda (response)
           (wait-for-action (json-ref response "action")))))

(define server-provider
  (register-provider!
   (make-provider 'hetzner-server
                  #:create create-server
                  #:update update-server
                  #:delete delete-server
                  #:replace-on '(location image ssh-keys))))

(define* (hetzner-server resource-name
                         #:key type location (image "debian-12")
                         (ssh-keys '()) (name resource-name))
  "Declare a server.  Changing TYPE resizes it in place; changing LOCATION,
IMAGE or SSH-KEYS replaces it, losing its data."
  (unless (and type location)
    (error "hetzner-server: #:type and #:location are required" resource-name))
  (ensure-resource server-provider resource-name
                   `((name . ,name)
                     (type . ,type)
                     (location . ,location)
                     (image . ,image)
                     (ssh-keys . ,ssh-keys))))
