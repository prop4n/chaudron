;;; Oracle Cloud Object Storage buckets.

(define-module (chaudron oracle bucket)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle api)
  #:export (oracle-bucket))

(define (bucket-path namespace name)
  (string-append "/n/" namespace "/b/" name))

(define (bucket-outputs namespace bucket)
  (let ((name (json-ref bucket "name")))
    `((id . ,name)
      (name . ,name)
      (namespace . ,namespace))))

(define (public-access public?)
  (if public? "ObjectRead" "NoPublicAccess"))

(define (create-bucket _ props)
  (let ((namespace (oracle-namespace)))
    (bucket-outputs namespace
                    (oracle-request 'objectstorage 'POST
                                    (string-append "/n/" namespace "/b/")
                                    `(("name" . ,(assq-ref props 'name))
                                      ("compartmentId"
                                       . ,(assq-ref props 'compartment))
                                      ("publicAccessType"
                                       . ,(public-access
                                           (assq-ref props 'public?))))))))

(define (read-bucket outputs)
  (and=> (oracle-get 'objectstorage
                     (bucket-path (assq-ref outputs 'namespace)
                                  (assq-ref outputs 'name)))
         (lambda (bucket)
           (cons `((name . ,(json-ref bucket "name"))
                   (compartment . ,(json-ref bucket "compartmentId"))
                   (public? . ,(string=? "ObjectRead"
                                         (json-ref bucket "publicAccessType"))))
                 outputs))))

(define (update-bucket outputs old new)
  ;; Renaming and moving to another compartment are done in place.
  (let ((namespace (assq-ref outputs 'namespace)))
    (bucket-outputs namespace
                    (oracle-request 'objectstorage 'POST
                                    (bucket-path namespace
                                                 (assq-ref outputs 'name))
                                    `(("name" . ,(assq-ref new 'name))
                                      ("compartmentId"
                                       . ,(assq-ref new 'compartment))
                                      ("publicAccessType"
                                       . ,(public-access
                                           (assq-ref new 'public?))))))))

(define (delete-bucket outputs)
  (oracle-delete 'objectstorage
                 (bucket-path (assq-ref outputs 'namespace)
                              (assq-ref outputs 'name))))

(define bucket-provider
  (register-provider!
   (make-provider 'oracle-bucket
                  #:create create-bucket
                  #:read read-bucket
                  #:update update-bucket
                  #:delete delete-bucket)))

(define* (oracle-bucket resource-name
                        #:key name public? (compartment (oracle-compartment)))
  "Declare an Object Storage bucket, named after RESOURCE-NAME and the
stage, or NAME.  With PUBLIC?, anyone can read its objects.  It is made in
COMPARTMENT, by default that of `oracle-compartment'.  It must be empty to
be deleted."
  (ensure-resource bucket-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (compartment . ,compartment)
                     (public? . ,(and public? #t)))))
