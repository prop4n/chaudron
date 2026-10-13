;; Tests for Oracle Cloud networks and instances, against a scripted fake
;; API.

(use-modules (chaudron)
             (chaudron oracle)
             (srfi srfi-64)
             (tests fake-api))

(setenv "OCI_REGION" "xx-test-1")
(setenv "OCI_TENANCY" "ocid1.tenancy.test")
(setenv "OCI_USER" "ocid1.user.test")
(setenv "OCI_FINGERPRINT" "00:11")
(setenv "OCI_KEY_FILE" "tests/oracle-key.pem")
(setenv "OCI_COMPARTMENT" "c1")

(define ok '(200 . #f))

(define (made id state . fields)
  `(200 . (("id" . ,id) ("lifecycleState" . ,state) ,@fields)))

(define vcn
  (made "v1" "AVAILABLE"
        '("displayName" . "net-prod")
        '("compartmentId" . "c1")
        '("cidrBlocks" . #("10.0.0.0/16"))
        '("defaultRouteTableId" . "rt1")
        '("defaultSecurityListId" . "sl1")))

(define (security-list . ports)
  `(200 . (("ingressSecurityRules"
            . ,(list->vector
                (map (lambda (port)
                       `(("protocol" . "6")
                         ("tcpOptions"
                          ("destinationPortRange" ("min" . ,port)
                                                  ("max" . ,port)))))
                     ports))))))

(define instance (made "i1" "RUNNING"
                       '("displayName" . "vm-prod")
                       '("shape" . "VM.Standard.E2.1.Micro")))

(define* (deploy #:key (ports '(22)))
  (quietly
   (lambda ()
     (with-stage "prod"
       (let* ((net (oracle-network "net" #:ports ports))
              (vm (oracle-instance "vm" #:network net)))
         (output vm 'ipv4))))))

(test-begin "oracle-compute")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "makes the network, then the instance, and finds its address"
    '("203.0.113.7"
      ((POST "/vcns")
       (GET "/vcns/v1")
       (POST "/internetGateways")
       (GET "/internetGateways/g1")
       (PUT "/routeTables/rt1")
       (PUT "/securityLists/sl1")
       (POST "/subnets")
       (GET "/subnets/s1")
       (GET "/availabilityDomains?compartmentId=ocid1.tenancy.test")
       (GET "/images?compartmentId=c1&shape=VM.Standard.E2.1.Micro&sortBy=TIMECREATED&sortOrder=DESC")
       (POST "/instances")
       (GET "/instances/i1")
       (GET "/vnicAttachments?compartmentId=c1&instanceId=i1")
       (GET "/vnics/n1")))
    (with-api ((made "v1" "PROVISIONING") vcn
               (made "g1" "PROVISIONING") (made "g1" "AVAILABLE")
               ok ok
               (made "s1" "PROVISIONING") (made "s1" "AVAILABLE")
               '(200 . #((("name" . "AD-1"))))
               '(200 . #((("id" . "img-minimal")
                          ("operatingSystem" . "Canonical Ubuntu")
                          ("operatingSystemVersion" . "24.04 Minimal"))
                         (("id" . "img1")
                          ("operatingSystem" . "Canonical Ubuntu")
                          ("operatingSystemVersion" . "24.04"))))
               (made "i1" "PROVISIONING")
               instance
               '(200 . #((("vnicId" . "n1"))))
               '(200 . (("publicIp" . "203.0.113.7")
                        ("privateIp" . "10.0.0.2"))))
      (list (deploy) (routes))))

  (test-equal "routes the network to its gateway, and opens its ports"
    '("g1" 22)
    (list (assoc-ref (vector-ref (assoc-ref (body 4) "routeRules") 0)
                     "networkEntityId")
          (assoc-ref (assoc-ref (assoc-ref (vector-ref
                                            (assoc-ref (body 5)
                                                       "ingressSecurityRules")
                                            1)
                                           "tcpOptions")
                                "destinationPortRange")
                     "min")))

  (test-equal "starts the image named, in the subnet, with a public address"
    '("img1" "s1" #t "AD-1")
    (list (assoc-ref (assoc-ref (body 10) "sourceDetails") "imageId")
          (assoc-ref (assoc-ref (body 10) "createVnicDetails") "subnetId")
          (assoc-ref (assoc-ref (body 10) "createVnicDetails") "assignPublicIp")
          (assoc-ref (body 10) "availabilityDomain")))

  (test-equal "only reads them when nothing changed"
    '((GET "/vcns/v1")
      (GET "/subnets/s1")
      (GET "/securityLists/sl1")
      (GET "/instances/i1"))
    (with-api (vcn (made "s1" "AVAILABLE") (security-list 22) instance)
      (deploy)
      (routes)))

  (test-equal "opens more ports in place"
    '(PUT "/securityLists/sl1")
    (with-api (vcn (made "s1" "AVAILABLE") (security-list 22) ok instance)
      (deploy #:ports '(80 22))
      (list-ref (routes) 3)))

  (test-equal "deletes the instance and waits for it, then the network"
    '((DELETE "/instances/i1?preserveBootVolume=false")
      (GET "/instances/i1")
      (DELETE "/subnets/s1")
      (GET "/subnets/s1")
      (PUT "/routeTables/rt1")
      (DELETE "/internetGateways/g1")
      (GET "/internetGateways/g1")
      (DELETE "/vcns/v1")
      (GET "/vcns/v1"))
    (with-api (ok (made "i1" "TERMINATED")
               ok (made "s1" "TERMINATED")
               ok
               ok (made "g1" "TERMINATED")
               ok '(404 . (("code" . "NotAuthorizedOrNotFound"))))
      (quietly (lambda () (with-stage "prod" #t)))
      (routes)))

  (test-equal "deletes a half-made network"
    '((POST "/vcns")
      (GET "/vcns/v1")
      (POST "/internetGateways")
      (DELETE "/vcns/v1")
      (GET "/vcns/v1"))
    (with-api ((made "v1" "PROVISIONING") vcn
               '(400 . (("code" . "LimitExceeded") ("message" . "too many")))
               ok (made "v1" "TERMINATED"))
      (false-if-exception
       (quietly (lambda ()
                  (with-stage "prod" (oracle-network "net")))))
      (routes))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "oracle-compute")
(exit (zero? failures))
