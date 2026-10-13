;;; Oracle Cloud custom images, imported from Object Storage.

(define-module (chaudron oracle image)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle api)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (web uri)
  #:export (oracle-image))

(define (image-path outputs . rest)
  (apply string-append "/images/" (assq-ref outputs 'id) rest))

(define (shape-path outputs shape)
  (image-path outputs "/shapes/" (uri-encode shape)))

(define (add-shape! outputs shape)
  (oracle-request 'iaas 'PUT (shape-path outputs shape)
                  `(("imageId" . ,(assq-ref outputs 'id))
                    ("shape" . ,shape))))

(define (remove-shape! outputs shape)
  (oracle-delete 'iaas (shape-path outputs shape)))

(define (set-firmware! outputs props firmware)
  "Tell Oracle that the image boots with FIRMWARE, \"UEFI_64\" or \"BIOS\":
imported images are taken as BIOS ones."
  (let ((schema (match (json-list (oracle-request
                                   'iaas 'GET
                                   "/computeGlobalImageCapabilitySchemas"))
                  ((schema . _) schema))))
    (oracle-request 'iaas 'POST "/computeImageCapabilitySchemas"
                    `(("compartmentId" . ,(assq-ref props 'compartment))
                      ("imageId" . ,(assq-ref outputs 'id))
                      ("computeGlobalImageCapabilitySchemaVersionName"
                       . ,(json-ref schema "currentVersionName"))
                      ("schemaData"
                       ("Compute.Firmware"
                        ("descriptorType" . "enumstring")
                        ("source" . "IMAGE")
                        ("defaultValue" . ,firmware)
                        ("values" . #(,firmware))))))))

(define (create-image _ props)
  (let* ((image (oracle-request
                 'iaas 'POST "/images"
                 `(("compartmentId" . ,(assq-ref props 'compartment))
                   ("displayName" . ,(assq-ref props 'name))
                   ("launchMode" . ,(assq-ref props 'launch-mode))
                   ("imageSourceDetails"
                    ("sourceType" . "objectStorageTuple")
                    ("namespaceName" . ,(assq-ref props 'namespace))
                    ("bucketName" . ,(assq-ref props 'bucket))
                    ("objectName" . ,(assq-ref props 'object-name))
                    ("sourceImageType" . "QCOW2")
                    ("operatingSystem" . ,(assq-ref props 'operating-system))))))
         (outputs `((id . ,(json-ref image "id")))))
    ;; Importing takes minutes: save the image before waiting for it.
    (created! outputs props '((shapes)))
    (report "~a: importing the image, this takes a while"
            (assq-ref props 'name))
    (let ((imported (wait-for-state 'iaas (image-path outputs)
                                    '("AVAILABLE" "DELETED" "DISABLED")
                                    #:tries 360 #:delay 10)))
      (unless (equal? "AVAILABLE" (and imported
                                       (json-ref imported "lifecycleState")))
        (error "the image could not be imported" (assq-ref props 'name))))
    (set-firmware! outputs props (assq-ref props 'firmware))
    (for-each (lambda (shape) (add-shape! outputs shape))
              (assq-ref props 'shapes))
    outputs))

(define (read-image outputs)
  (let ((image (oracle-get 'iaas (image-path outputs))))
    (and image
         (not (member (json-ref image "lifecycleState")
                      '("DELETED" "DISABLED")))
         (cons `((name . ,(json-ref image "displayName")))
               outputs))))

(define (update-image outputs old new)
  (unless (equal? (assq-ref old 'name) (assq-ref new 'name))
    (oracle-request 'iaas 'PUT (image-path outputs)
                    `(("displayName" . ,(assq-ref new 'name)))))
  (let ((old-shapes (assq-ref old 'shapes))
        (new-shapes (assq-ref new 'shapes)))
    (for-each (lambda (shape) (add-shape! outputs shape))
              (lset-difference string=? new-shapes old-shapes))
    (for-each (lambda (shape) (remove-shape! outputs shape))
              (lset-difference string=? old-shapes new-shapes)))
  outputs)

(define (delete-image outputs)
  (oracle-delete 'iaas (image-path outputs)))

(define image-provider
  (register-provider!
   (make-provider 'oracle-image
                  #:create create-image
                  #:read read-image
                  #:update update-image
                  #:delete delete-image
                  #:replace-on '(compartment namespace bucket object-name
                                 sha256 launch-mode operating-system
                                 firmware))))

(define* (oracle-image resource-name
                       #:key object (shapes '()) (firmware "UEFI_64")
                       (launch-mode "PARAVIRTUALIZED")
                       (operating-system "Linux") name
                       (compartment (oracle-compartment)))
  "Declare an image imported from OBJECT, an `oracle-object' holding a QCOW2
disk image, named after RESOURCE-NAME and the stage, or NAME.  Instances of
the SHAPES can start from it.  FIRMWARE is what it boots with, \"UEFI_64\"
or \"BIOS\"; Arm shapes such as \"VM.Standard.A1.Flex\" only have UEFI.  It
is imported again whenever the object changes."
  (unless object
    (error "oracle-image: #:object is required" resource-name))
  (ensure-resource image-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (compartment . ,compartment)
                     (object . ,object)
                     (namespace . ,(output object 'namespace))
                     (bucket . ,(output object 'bucket))
                     (object-name . ,(output object 'name))
                     (sha256 . ,(output object 'sha256))
                     (firmware . ,firmware)
                     (launch-mode . ,launch-mode)
                     (operating-system . ,operating-system)
                     (shapes . ,(sort (delete-duplicates shapes) string<?)))))
