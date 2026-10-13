;;; Files in Oracle Cloud Object Storage buckets.

(define-module (chaudron oracle object)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle api)
  #:use-module (gcrypt base16)
  #:use-module (gcrypt hash)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 receive)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (web uri)
  #:export (oracle-object
            %part-size))

;; Files larger than this are sent in parts of this size.
(define %part-size (make-parameter (* 64 1024 1024)))

(define (object-path outputs)
  (string-append "/n/" (assq-ref outputs 'namespace)
                 "/b/" (assq-ref outputs 'bucket)
                 "/o/" (uri-encode (assq-ref outputs 'name))))

(define (upload-path outputs)
  (string-append "/n/" (assq-ref outputs 'namespace)
                 "/b/" (assq-ref outputs 'bucket)
                 "/u/" (uri-encode (assq-ref outputs 'name))))

(define (etag headers)
  (match (assq-ref headers 'etag)
    ((tag . _) tag)                     ;as Guile parses it
    (tag tag)))

(define (put-whole! outputs props)
  (oracle-call 'objectstorage 'PUT (object-path outputs)
               #:data (let ((bytes (call-with-input-file (assq-ref props 'file)
                                     get-bytevector-all #:binary #t)))
                        (if (eof-object? bytes) #vu8() bytes))
               #:headers `((opc-meta-sha256 . ,(assq-ref props 'sha256)))))

(define (put-in-parts! outputs props)
  (let* ((upload (oracle-request 'objectstorage 'POST
                                 (string-append "/n/" (assq-ref outputs 'namespace)
                                                "/b/" (assq-ref outputs 'bucket)
                                                "/u")
                                 `(("object" . ,(assq-ref outputs 'name))
                                   ("metadata"
                                    ("opc-meta-sha256"
                                     . ,(assq-ref props 'sha256))))))
         (path (string-append (upload-path outputs)
                              "?uploadId=" (json-ref upload "uploadId"))))
    (define (send-parts port)
      (let loop ((number 1) (parts '()))
        (let ((bytes (get-bytevector-n port (%part-size))))
          (if (eof-object? bytes)
              (reverse parts)
              (receive (_ headers)
                  (oracle-call 'objectstorage 'PUT
                               (string-append path "&uploadPartNum="
                                              (number->string number))
                               #:data bytes)
                (loop (1+ number)
                      (cons `(("partNum" . ,number)
                              ("etag" . ,(etag headers)))
                            parts)))))))
    ;; If a part fails, abort the upload, or Oracle keeps the parts sent.
    (with-exception-handler
        (lambda (e)
          (false-if-exception (oracle-request 'objectstorage 'DELETE path))
          (raise-exception e))
      (lambda ()
        (let ((parts (call-with-input-file (assq-ref props 'file)
                       send-parts #:binary #t)))
          (oracle-request 'objectstorage 'POST path
                          `(("partsToCommit" . ,(list->vector parts)))))))))

(define (upload! outputs props)
  (if (> (stat:size (stat (assq-ref props 'file))) (%part-size))
      (put-in-parts! outputs props)
      (put-whole! outputs props)))

(define (create-object _ props)
  (let ((outputs `((namespace . ,(oracle-namespace))
                   (bucket . ,(assq-ref props 'bucket))
                   (name . ,(assq-ref props 'name)))))
    (upload! outputs props)
    `((id . ,(assq-ref props 'name))
      ,@outputs
      (sha256 . ,(assq-ref props 'sha256)))))

(define (read-object outputs)
  (unless-gone
   (lambda ()
     (receive (_ headers)
         (oracle-call 'objectstorage 'HEAD (object-path outputs))
       (cons `((sha256 . ,(assq-ref headers 'opc-meta-sha256))) outputs)))))

(define (update-object outputs old new)
  (upload! outputs new)
  `(,@(alist-delete 'sha256 outputs)
    (sha256 . ,(assq-ref new 'sha256))))

(define (delete-object outputs)
  (oracle-delete 'objectstorage (object-path outputs)))

(define object-provider
  (register-provider!
   (make-provider 'oracle-object
                  #:create create-object
                  #:read read-object
                  #:update update-object
                  #:delete delete-object
                  #:replace-on '(bucket name))))

(define* (oracle-object resource-name #:key bucket file name)
  "Declare an object in BUCKET, an `oracle-bucket', holding the content of
FILE.  It is named RESOURCE-NAME, or NAME.  It is sent again whenever FILE
changes."
  (unless (and bucket file)
    (error "oracle-object: #:bucket and #:file are required" resource-name))
  (ensure-resource object-provider resource-name
                   `((bucket . ,bucket)
                     (name . ,(or name resource-name))
                     (file . ,file)
                     (sha256 . ,(bytevector->base16-string
                                 (file-sha256 file))))))
