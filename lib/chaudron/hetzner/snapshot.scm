;;; Hetzner Cloud snapshots: images of a server's disk.

(define-module (chaudron hetzner snapshot)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:export (hetzner-snapshot))

(define (create-snapshot _ props)
  ;; Taking the snapshot can be long: save it before waiting for it.
  (let* ((response (hetzner-request
                    'POST (resource-path "servers" (assq-ref props 'server)
                                         "/actions/create_image")
                    `(("type" . "snapshot")
                      ("description" . ,(assq-ref props 'description))
                      ("labels" . ,(labels->json props)))))
         (id (json-ref response "image" "id")))
    (created! `((id . ,id)) props '((protected? . #f)))
    (wait-for-actions response)
    (when (assq-ref props 'protected?)
      (protect! "images" id props))
    `((id . ,id))))

(define (read-snapshot outputs)
  (and=> (json-ref (hetzner-get (resource-path "images" (assq-ref outputs 'id)))
                   "image")
         (lambda (image)
           (cons `((description . ,(json-ref image "description"))
                   ,@(observe-protection image))
                 outputs))))

(define (update-snapshot outputs old new)
  (let ((id (assq-ref outputs 'id)))
    (unless (and (equal? (assq-ref old 'description) (assq-ref new 'description))
                 (equal? (assq-ref old 'labels) (assq-ref new 'labels)))
      (hetzner-request 'PUT (resource-path "images" id)
                       `(("description" . ,(assq-ref new 'description))
                         ("labels" . ,(labels->json new)))))
    (update-protection! "images" id old new))
  outputs)

(define (delete-snapshot outputs)
  (hetzner-delete (resource-path "images" (assq-ref outputs 'id))))

(define snapshot-provider
  (register-provider!
   (make-provider 'hetzner-snapshot
                  #:create create-snapshot
                  #:read read-snapshot
                  #:update update-snapshot
                  #:delete delete-snapshot
                  #:replace-on '(server))))

(define* (hetzner-snapshot resource-name
                           #:key server (description resource-name)
                           (labels '()) protected?)
  "Declare a snapshot of SERVER's disk, taken once when it is created; it
can be used as the #:image of other servers.  For a consistent copy, power
the server off first."
  (unless server
    (error "hetzner-snapshot: #:server is required" resource-name))
  (ensure-resource snapshot-provider resource-name
                   `((server . ,server)
                     (description . ,description)
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))
