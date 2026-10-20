;;; Hetzner Storage Boxes: storage reachable over SSH, Samba or WebDAV,
;;; which servers can mount.

(define-module (chaudron hetzner storage-box)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:use-module (gcrypt base16)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 match)
  #:use-module (rnrs bytevectors)
  #:export (hetzner-storage-box))

(define %ready-timeout 600)             ;seconds

(define (nullable value)
  (if (eq? value 'null) #f value))

(define (storage-box-outputs box)
  `((id . ,(json-ref box "id"))
    (username . ,(nullable (json-ref box "username")))
    (server . ,(nullable (json-ref box "server")))))

(define %access
  ;; Props and the API fields they stand for.
  '((ssh? . "ssh_enabled")
    (samba? . "samba_enabled")
    (webdav? . "webdav_enabled")
    (zfs? . "zfs_enabled")
    (external? . "reachable_externally")))

(define (access->json access)
  (map (match-lambda
         ((prop . field) (cons field (assq-ref access prop))))
       %access))

(define (observe-access box)
  (map (match-lambda
         ((prop . field)
          (cons prop (eq? #t (json-ref box "access_settings" field)))))
       %access))

(define (wait-until-ready id)
  "Return Storage Box ID once it is active: its username and server are not
known before."
  (let loop ((seconds 0))
    (let ((box (json-ref (hetzner-request 'GET (resource-path "storage_boxes" id))
                         "storage_box")))
      (cond ((equal? "active" (json-ref box "status")) box)
            ((>= seconds %ready-timeout)
             (error "Storage Box still not ready" id))
            (else
             ((hetzner-sleep) 5)
             (loop (+ seconds 5)))))))

(define (create-storage-box _ props)
  (let* ((response (hetzner-request
                    'POST "/storage_boxes"
                    `(("name" . ,(assq-ref props 'name))
                      ("storage_box_type" . ,(assq-ref props 'type))
                      ("location" . ,(assq-ref props 'location))
                      ("password" . ,(password props))
                      ("ssh_keys" . ,(list->vector (assq-ref props 'ssh-keys)))
                      ("access_settings"
                       . ,(access->json (assq-ref props 'access)))
                      ("labels" . ,(labels->json props)))))
         (id (json-ref response "storage_box" "id")))
    (created! `((id . ,id) (username . #f) (server . #f))
              props '((protected? . #f)))
    (wait-for-actions response "/storage_boxes")
    (let ((outputs (storage-box-outputs (wait-until-ready id))))
      (when (assq-ref props 'protected?)
        (protect! "storage_boxes" id props))
      outputs)))

(define (read-storage-box outputs)
  (and=> (json-ref (hetzner-get (resource-path "storage_boxes"
                                               (assq-ref outputs 'id)))
                   "storage_box")
         (lambda (box)
           (cons `(,@(observe-metadata box)
                   (type . ,(json-ref box "storage_box_type" "name"))
                   (access . ,(observe-access box))
                   ,@(observe-protection box))
                 (storage-box-outputs box)))))

(define (update-storage-box outputs old new)
  (let ((id (assq-ref outputs 'id)))
    (define (changed? key)
      (not (equal? (assq-ref old key) (assq-ref new key))))

    (update-metadata! "storage_boxes" id old new)
    (when (changed? 'type)
      (resource-action "storage_boxes" id "change_type"
                       `(("storage_box_type" . ,(assq-ref new 'type)))))
    (when (changed? 'access)
      (resource-action "storage_boxes" id "update_access_settings"
                       (access->json (assq-ref new 'access))))
    (when (changed? 'password-digest)
      (resource-action "storage_boxes" id "reset_password"
                       `(("password" . ,(password new)))))
    (update-protection! "storage_boxes" id old new)
    (when (changed? 'ssh-keys)
      (report "~a: SSH keys are only given to a new Storage Box; add these \
to its .ssh/authorized_keys" (assq-ref new 'name))))
  outputs)

(define (delete-storage-box outputs)
  (and=> (hetzner-delete (resource-path "storage_boxes" (assq-ref outputs 'id)))
         (lambda (response)
           (wait-for-actions response "/storage_boxes"))))

(define storage-box-provider
  (register-provider!
   (make-provider 'hetzner-storage-box
                  #:create create-storage-box
                  #:read read-storage-box
                  #:update update-storage-box
                  #:delete delete-storage-box
                  #:replace-on '(location))))

;;; Declaring.

;; Passwords by digest: they are not saved in the state, as props are.
(define %passwords (make-hash-table))

(define (password-digest password)
  (let ((digest (bytevector->base16-string (sha256 (string->utf8 password)))))
    (hash-set! %passwords digest password)
    digest))

(define (password props)
  (hash-ref %passwords (assq-ref props 'password-digest)))

(define* (hetzner-storage-box resource-name
                              #:key type location password (ssh-keys '())
                              ssh? samba? webdav? zfs? external?
                              (labels '()) protected? name)
  "Declare a Storage Box of TYPE, such as \"bx11\" for 1 TB, in LOCATION,
with PASSWORD, of which only a digest is saved: changing it resets it.
SSH-KEYS, public keys as strings, are only given to a new Storage Box.
SSH?, SAMBA? and WEBDAV? enable these ways in, ZFS? shows its snapshots, and
EXTERNAL? makes it reachable from outside Hetzner.  Changing LOCATION
replaces it, losing its data."
  (unless (and type location password)
    (error "hetzner-storage-box: #:type, #:location and #:password are \
required" resource-name))
  (ensure-resource storage-box-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (type . ,type)
                     (location . ,location)
                     (password-digest . ,(password-digest password))
                     (ssh-keys . ,ssh-keys)
                     (access . ((ssh? . ,(and ssh? #t))
                                (samba? . ,(and samba? #t))
                                (webdav? . ,(and webdav? #t))
                                (zfs? . ,(and zfs? #t))
                                (external? . ,(and external? #t))))
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))
