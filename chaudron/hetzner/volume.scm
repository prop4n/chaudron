;;; Hetzner Cloud volumes: block storage that outlives servers.

(define-module (chaudron hetzner volume)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (chaudron hetzner common)
  #:export (hetzner-volume
            attach-volume!
            detach-volume!))

(define (volume-outputs volume)
  `((id . ,(json-ref volume "id"))
    (linux-device . ,(json-ref volume "linux_device"))))

(define (create-volume _ props)
  (let* ((response (hetzner-request 'POST "/volumes"
                                    `(("name" . ,(assq-ref props 'name))
                                      ("size" . ,(assq-ref props 'size))
                                      ("location" . ,(assq-ref props 'location))
                                      ("format" . ,(assq-ref props 'format))
                                      ("labels" . ,(labels->json props)))))
         (outputs (volume-outputs (json-ref response "volume"))))
    (wait-for-actions response)
    (when (assq-ref props 'protected?)
      (protect! "volumes" (assq-ref outputs 'id) props))
    outputs))

(define (read-volume outputs)
  (and=> (json-ref (hetzner-get (resource-path "volumes" (assq-ref outputs 'id)))
                   "volume")
         (lambda (volume)
           (cons `(,@(observe-metadata volume)
                   (size . ,(json-ref volume "size"))
                   ,@(observe-protection volume))
                 (volume-outputs volume)))))

(define (update-volume outputs old new)
  (let ((id (assq-ref outputs 'id))
        (size (assq-ref new 'size)))
    (update-metadata! "volumes" id old new)
    (update-protection! "volumes" id old new)
    (unless (= size (assq-ref old 'size))
      (when (< size (assq-ref old 'size))
        (error "volumes can only grow" (assq-ref new 'name)))
      (resource-action "volumes" id "resize" `(("size" . ,size)))))
  outputs)

(define (delete-volume outputs)
  (hetzner-delete (resource-path "volumes" (assq-ref outputs 'id))))

(define volume-provider
  (register-provider!
   (make-provider 'hetzner-volume
                  #:create create-volume
                  #:read read-volume
                  #:update update-volume
                  #:delete delete-volume
                  #:replace-on '(location format))))

(define* (hetzner-volume resource-name
                         #:key size location (format "ext4") (labels '())
                         protected? (name resource-name))
  "Declare a volume of SIZE gigabytes in LOCATION.  Give it to a server with
its #:volumes argument; it is then mounted under /mnt.  SIZE can only grow."
  (unless (and size location)
    (error "hetzner-volume: #:size and #:location are required" resource-name))
  (ensure-resource volume-provider resource-name
                   `((name . ,name)
                     (size . ,size)
                     (location . ,location)
                     (format . ,format)
                     (labels . ,(sorted-labels labels))
                     (protected? . ,(and protected? #t)))))

;;; Attaching volumes to servers.

(define (attach-volume! volume server)
  (resource-action "volumes" volume "attach"
                   `(("server" . ,server) ("automount" . #t))))

(define (detach-volume! volume)
  (resource-action "volumes" volume "detach"))
