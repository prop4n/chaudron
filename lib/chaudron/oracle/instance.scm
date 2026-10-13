;;; Oracle Cloud compute instances.

(define-module (chaudron oracle instance)
  #:use-module (chaudron command)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle api)
  #:use-module (gcrypt base64)
  #:use-module (ice-9 match)
  #:use-module (ice-9 textual-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (web uri)
  #:export (oracle-instance))

(define (query . parameters)
  "Return PARAMETERS, alternating names and values, as a query string."
  (string-join (let loop ((parameters parameters))
                 (match parameters
                   (() '())
                   ((name value . rest)
                    (cons (string-append name "=" (uri-encode value))
                          (loop rest)))))
               "&"))

(define (availability-domain)
  "Return the first availability domain of the tenancy."
  (match (json-list (oracle-request 'identity 'GET
                                    (string-append "/availabilityDomains?"
                                                   (query "compartmentId"
                                                          (getenv "OCI_TENANCY")))))
    ((domain . _) (json-ref domain "name"))))

(define (image-id image compartment shape)
  "Return the ID of IMAGE: an image ID already, or the name of an Oracle
image such as \"Canonical Ubuntu 24.04\", whose latest version for SHAPE is
taken."
  (if (string-prefix? "ocid1." image)
      image
      (or (any (lambda (found)
                 (and (string=? image
                                (string-append
                                 (json-ref found "operatingSystem") " "
                                 (json-ref found "operatingSystemVersion")))
                      (json-ref found "id")))
               (json-list
                (oracle-request 'iaas 'GET
                                (string-append "/images?"
                                               (query "compartmentId" compartment
                                                      "shape" shape
                                                      "sortBy" "TIMECREATED"
                                                      "sortOrder" "DESC")))))
          (error "no such Oracle image for this shape" image shape))))

(define (shape-config props)
  (if (assq-ref props 'ocpus)
      `(("shapeConfig" ("ocpus" . ,(assq-ref props 'ocpus))
                       ("memoryInGBs" . ,(assq-ref props 'memory))))
      '()))

(define (addresses id compartment)
  "Return the public and private IPv4 addresses of instance ID."
  (let* ((attachments (oracle-request 'iaas 'GET
                                      (string-append "/vnicAttachments?"
                                                     (query "compartmentId"
                                                            compartment
                                                            "instanceId" id))))
         (vnic (match (json-list attachments)
                 ((attachment . _)
                  (oracle-request 'iaas 'GET
                                  (string-append "/vnics/"
                                                 (json-ref attachment
                                                           "vnicId")))))))
    `((ipv4 . ,(json-ref vnic "publicIp"))
      (private-ipv4 . ,(json-ref vnic "privateIp")))))

(define (running instance)
  (wait-for-state 'iaas (string-append "/instances/" (json-ref instance "id"))
                  '("RUNNING" "TERMINATED")))

(define (create-instance _ props)
  (let* ((compartment (assq-ref props 'compartment))
         (domain (or (assq-ref props 'availability-domain)
                     (availability-domain)))
         (image (image-id (assq-ref props 'image) compartment
                          (assq-ref props 'shape)))
         (instance
          (oracle-request
           'iaas 'POST "/instances"
           `(("compartmentId" . ,compartment)
             ("availabilityDomain" . ,domain)
             ("displayName" . ,(assq-ref props 'name))
             ("shape" . ,(assq-ref props 'shape))
             ,@(shape-config props)
             ("sourceDetails"
              ("sourceType" . "image")
              ("imageId" . ,image)
              ,@(if (assq-ref props 'disk)
                    `(("bootVolumeSizeInGBs" . ,(assq-ref props 'disk)))
                    '()))
             ("createVnicDetails"
              ("subnetId" . ,(assq-ref props 'network))
              ("assignPublicIp" . #t))
             ("metadata"
              ,@(if (assq-ref props 'ssh-key)
                    `(("ssh_authorized_keys" . ,(assq-ref props 'ssh-key)))
                    '())
              ,@(if (assq-ref props 'user-data)
                    `(("user_data"
                       . ,(base64-encode
                           (string->utf8 (assq-ref props 'user-data)))))
                    '())))))
         (outputs `((id . ,(json-ref instance "id"))
                    (compartment . ,compartment)
                    (availability-domain . ,domain)
                    (image-id . ,image))))
    ;; Save it at once: starting it takes a while, and may fail.
    (created! outputs props)
    (unless (equal? "RUNNING" (json-ref (running instance) "lifecycleState"))
      (error "the instance stopped while starting" (assq-ref props 'name)))
    (append outputs (addresses (json-ref instance "id") compartment))))

(define (read-instance outputs)
  (let ((instance (oracle-get 'iaas (string-append "/instances/"
                                                   (assq-ref outputs 'id)))))
    (and instance
         (not (member (json-ref instance "lifecycleState")
                      '("TERMINATING" "TERMINATED")))
         (cons `((name . ,(json-ref instance "displayName"))
                 (shape . ,(json-ref instance "shape")))
               outputs))))

(define (update-instance outputs old new)
  ;; Changing the shape restarts the instance.
  (let ((instance (oracle-request
                   'iaas 'PUT (string-append "/instances/"
                                             (assq-ref outputs 'id))
                   `(("displayName" . ,(assq-ref new 'name))
                     ("shape" . ,(assq-ref new 'shape))
                     ,@(shape-config new)))))
    (running instance)
    (append (remove (lambda (output)
                      (memq (car output) '(ipv4 private-ipv4)))
                    outputs)
            (addresses (assq-ref outputs 'id)
                       (assq-ref outputs 'compartment)))))

(define (delete-instance outputs)
  (let ((path (string-append "/instances/" (assq-ref outputs 'id))))
    (oracle-delete 'iaas (string-append path "?preserveBootVolume=false"))
    ;; Its network cannot be deleted before it is gone.
    (wait-for-state 'iaas path '("TERMINATED"))))

(define instance-provider
  (register-provider!
   (make-provider 'oracle-instance
                  #:create create-instance
                  #:read read-instance
                  #:update update-instance
                  #:delete delete-instance
                  #:replace-on '(compartment availability-domain image disk
                                 network ssh-key user-data))))

(define* (oracle-instance resource-name
                          #:key network (shape "VM.Standard.E2.1.Micro")
                          ocpus memory (image "Canonical Ubuntu 24.04")
                          disk ssh-public-key-file user-data
                          availability-domain name
                          (compartment (oracle-compartment)))
  "Declare an instance in NETWORK, an `oracle-network', named after
RESOURCE-NAME and the stage, or NAME.  SHAPE is its kind of machine; flexible
shapes such as \"VM.Standard.A1.Flex\" also take OCPUS and MEMORY, in GB.
IMAGE is an image ID or the name of an Oracle image, DISK the size of its
boot volume in GB.  The key of SSH-PUBLIC-KEY-FILE is let in, and USER-DATA,
a cloud-init configuration, is run on first boot.  Changing SHAPE, OCPUS or
MEMORY restarts it; changing what it is made from replaces it."
  (unless network
    (error "oracle-instance: #:network is required" resource-name))
  (ensure-resource instance-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (compartment . ,compartment)
                     (availability-domain . ,availability-domain)
                     (network . ,network)
                     (shape . ,shape)
                     (ocpus . ,ocpus)
                     (memory . ,memory)
                     (image . ,image)
                     (disk . ,disk)
                     (ssh-key . ,(and ssh-public-key-file
                                      (string-trim-both
                                       (call-with-input-file
                                           (expand-home ssh-public-key-file)
                                         get-string-all))))
                     (user-data . ,user-data))))
