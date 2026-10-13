;; Tests for Oracle Cloud signing, buckets and objects, against a scripted
;; fake API.  tests/oracle-key.pem is a key made for these tests only.

(use-modules (chaudron)
             (chaudron oracle)
             (chaudron oracle object)
             (chaudron oracle signing)
             (gcrypt base16)
             (gcrypt hash)
             (ice-9 regex)
             (srfi srfi-1)
             (srfi srfi-64)
             (tests fake-api))

(setenv "OCI_REGION" "xx-test-1")
(setenv "OCI_TENANCY" "ocid1.tenancy.test")
(setenv "OCI_USER" "ocid1.user.test")
(setenv "OCI_FINGERPRINT" "00:11")
(setenv "OCI_KEY_FILE" "tests/oracle-key.pem")
(setenv "OCI_COMPARTMENT" "ocid1.compartment.test")

(define directory (mkdtemp "/tmp/chaudron-oracle-XXXXXX"))

(define (write-file! name content)
  (let ((file (string-append directory "/" name)))
    (call-with-output-file file (lambda (port) (display content port)))
    file))

(define hello (write-file! "hello.txt" "hello"))
(define hello-sha256
  "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

(define ok '(200 . #f))
(define namespace '(200 . "ns"))
(define bucket
  '(200 . (("name" . "files-prod")
           ("compartmentId" . "ocid1.compartment.test")
           ("publicAccessType" . "NoPublicAccess"))))
(define public-bucket
  '(200 . (("name" . "files-prod")
           ("compartmentId" . "ocid1.compartment.test")
           ("publicAccessType" . "ObjectRead"))))

(define (object-head sha256)
  (with-headers `((opc-meta-sha256 . ,sha256)) ok))

(define* (deploy #:key public? (file hello))
  (quietly
   (lambda ()
     (with-stage "prod"
       (let ((files (oracle-bucket "files" #:public? public?)))
         (oracle-object "hello.txt" #:bucket files #:file file))))))

(define (header request name)
  (assq-ref (list-ref request 3) name))

(define (signed-headers request)
  "Return the names of the headers that REQUEST signs."
  (match:substring (string-match "headers=\"([^\"]*)\""
                                 (header request 'Authorization))
                   1))

(test-begin "oracle")

(test-equal "signs like openssl"
  "Y8TpRrMFe9uqu9HFMaDB59vxicze48MOZFijyQDaLm1/ds0vVN/mGx6gT36nlgQ4ugvI35oR373sTFFxV8km6pzyNNkAsDTXx4m8Wd6N9dzkFA9FmasTA3KND2og2ecrj15IlbyCzPc6pMEJKStm33rw+smsOoVFvauSSYjlqGnBTDUUUuV0vwgAt59Y9Q9p0wkeQwqLRW8Ck1Rl9V1GykB4XKajoXloLhh831c0s0AJxjzQX1f3VkDtj83wKRoYhabeH56KpdCyTSXMbtFkkRRIYTgLltUU3BUwIPU2yeaPMN4SlBMs/CLh94or7i8TVV65bmk5gixkGOZqb6Qjuw=="
  (rsa-sign (read-rsa-key "tests/oracle-key.pem")
            "date: Thu, 01 Jan 2026 00:00:00 GMT
(request-target): get /n/
host: objectstorage.xx-test-1.oraclecloud.com"))

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates the bucket, then sends the file"
    '((GET "/n/")
      (POST "/n/ns/b/")
      (PUT "/n/ns/b/files-prod/o/hello.txt"))
    (with-api (namespace bucket ok)
      (deploy)
      (routes)))

  (test-equal "names the bucket after the stage, in the compartment"
    '("files-prod" "ocid1.compartment.test" "NoPublicAccess")
    (map (lambda (key) (assoc-ref (body 1) key))
         '("name" "compartmentId" "publicAccessType")))

  (test-equal "keeps the hash of the file in the object's metadata"
    hello-sha256
    (header (list-ref (recorded-requests) 2) 'opc-meta-sha256))

  (test-equal "signs the body of JSON requests, not that of files"
    '("date (request-target) host"
      "date (request-target) host content-length content-type x-content-sha256"
      "date (request-target) host")
    (map signed-headers (recorded-requests)))

  (test-equal "only reads them when nothing changed"
    '((GET "/n/ns/b/files-prod")
      (HEAD "/n/ns/b/files-prod/o/hello.txt"))
    (with-api (bucket (object-head hello-sha256))
      (deploy)
      (routes)))

  (test-equal "sends the file again when it was changed behind its back"
    '((GET "/n/ns/b/files-prod")
      (HEAD "/n/ns/b/files-prod/o/hello.txt")
      (PUT "/n/ns/b/files-prod/o/hello.txt"))
    (with-api (bucket (object-head "something else") ok)
      (deploy)
      (routes)))

  (test-equal "makes the bucket public in place"
    '((GET "/n/ns/b/files-prod")
      (POST "/n/ns/b/files-prod")
      (HEAD "/n/ns/b/files-prod/o/hello.txt"))
    (with-api (bucket public-bucket (object-head hello-sha256))
      (deploy #:public? #t)
      (routes)))

  (test-equal "sends large files in parts, then commits them"
    '((GET "/n/ns/b/files-prod")
      (HEAD "/n/ns/b/files-prod/o/hello.txt")
      (POST "/n/ns/b/files-prod/u")
      (PUT "/n/ns/b/files-prod/u/hello.txt?uploadId=u1&uploadPartNum=1")
      (PUT "/n/ns/b/files-prod/u/hello.txt?uploadId=u1&uploadPartNum=2")
      (PUT "/n/ns/b/files-prod/u/hello.txt?uploadId=u1&uploadPartNum=3")
      (POST "/n/ns/b/files-prod/u/hello.txt?uploadId=u1"))
    (parameterize ((%part-size 4))
      (with-api (public-bucket (object-head hello-sha256)
                 '(200 . (("uploadId" . "u1")))
                 (with-headers '((etag . ("e1" . #f))) ok)
                 (with-headers '((etag . ("e2" . #f))) ok)
                 (with-headers '((etag . ("e3" . #f))) ok)
                 ok)
        (deploy #:public? #t #:file (write-file! "hello.txt" "hello, world"))
        (routes))))

  (test-equal "commits the parts with their etags"
    '#((("etag" . "e1") ("partNum" . 1))
       (("etag" . "e2") ("partNum" . 2))
       (("etag" . "e3") ("partNum" . 3)))
    (assoc-ref (body 6) "partsToCommit"))

  (test-equal "aborts the upload when a part fails"
    '((POST "/n/ns/b/files-prod/u")
      (PUT "/n/ns/b/files-prod/u/hello.txt?uploadId=u2&uploadPartNum=1")
      (DELETE "/n/ns/b/files-prod/u/hello.txt?uploadId=u2"))
    (parameterize ((%part-size 4))
      (with-api (public-bucket (object-head hello-sha256)
                 '(200 . (("uploadId" . "u2")))
                 '(400 . (("code" . "InvalidPart") ("message" . "bad part")))
                 ok)
        (false-if-exception
         (deploy #:public? #t #:file (write-file! "hello.txt" "hello again")))
        (cddr (routes)))))

  (test-equal "deletes the object, then the bucket"
    '((DELETE "/n/ns/b/files-prod/o/hello.txt")
      (DELETE "/n/ns/b/files-prod"))
    (with-api (ok ok)
      (quietly (lambda () (with-stage "prod" #t)))
      (routes))))

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (define disk-file (write-file! "disk.qcow2" "disk"))
  (define disk-sha256
    (bytevector->base16-string (file-sha256 disk-file)))

  (define (deploy-image shapes)
    (quietly
     (lambda ()
       (with-stage "prod"
         (let* ((files (oracle-bucket "files"))
                (disk (oracle-object "disk.qcow2" #:bucket files
                                     #:file disk-file)))
           (output (oracle-image "guix" #:object disk #:shapes shapes) 'id))))))

  (define image '(200 . (("id" . "img1") ("displayName" . "guix-prod")
                         ("lifecycleState" . "AVAILABLE"))))

  (test-equal "imports the image from the object, then sets how it boots"
    '("img1"
      ((POST "/n/ns/b/")
       (PUT "/n/ns/b/files-prod/o/disk.qcow2")
       (POST "/images")
       (GET "/images/img1")
       (GET "/images/img1")
       (GET "/computeGlobalImageCapabilitySchemas")
       (POST "/computeImageCapabilitySchemas")
       (PUT "/images/img1/shapes/VM.Standard.A1.Flex")))
    (with-api (bucket ok
               '(200 . (("id" . "img1") ("lifecycleState" . "IMPORTING")))
               '(200 . (("id" . "img1") ("lifecycleState" . "IMPORTING")))
               image
               '(200 . #((("currentVersionName" . "v1"))))
               ok ok)
      (list (deploy-image '("VM.Standard.A1.Flex")) (routes))))

  (test-equal "imports it from the object, as UEFI"
    '(("files-prod" "disk.qcow2" "ns") "UEFI_64")
    (let ((source (assoc-ref (body 2) "imageSourceDetails")))
      (list (map (lambda (key) (assoc-ref source key))
                 '("bucketName" "objectName" "namespaceName"))
            (assoc-ref (assoc-ref (assoc-ref (body 6) "schemaData")
                                  "Compute.Firmware")
                       "defaultValue"))))

  (test-equal "adds and removes shapes in place"
    '((PUT "/images/img1/shapes/VM.Standard.E2.1.Micro")
      (DELETE "/images/img1/shapes/VM.Standard.A1.Flex"))
    (with-api (bucket (object-head disk-sha256) image ok ok)
      (deploy-image '("VM.Standard.E2.1.Micro"))
      (cdddr (routes))))

  (test-equal "imports it again when the file changes"
    '((PUT "/n/ns/b/files-prod/o/disk.qcow2")
      (GET "/images/img1")
      (DELETE "/images/img1")
      (POST "/images"))
    (begin
      (write-file! "disk.qcow2" "another disk")
      (with-api (bucket (object-head disk-sha256) ok
                 image
                 ok
                 '(200 . (("id" . "img2") ("lifecycleState" . "IMPORTING")))
                 '(200 . (("id" . "img2") ("lifecycleState" . "AVAILABLE")))
                 '(200 . #((("currentVersionName" . "v1"))))
                 ok ok)
        (deploy-image '("VM.Standard.E2.1.Micro"))
        (take (drop (routes) 2) 4)))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "oracle")
(exit (zero? failures))
