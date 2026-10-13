;;; Oracle Cloud networks: a virtual cloud network with one public subnet.

(define-module (chaudron oracle network)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron oracle api)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (oracle-network))

;;; An Oracle network is made of several objects: the VCN, an internet
;;; gateway, a route to it in the VCN's route table, the rules of the VCN's
;;; security list, and a subnet covering the whole VCN.  Machines in the
;;; subnet get public addresses and reach the internet.

(define (ingress-rules ports)
  "Return the security rules letting anyone reach the TCP PORTS, and the
ICMP messages needed for path MTU discovery."
  (list->vector
   (cons `(("protocol" . "1")
           ("source" . "0.0.0.0/0")
           ("icmpOptions" ("type" . 3) ("code" . 4)))
         (map (lambda (port)
                `(("protocol" . "6")
                  ("source" . "0.0.0.0/0")
                  ("tcpOptions"
                   ("destinationPortRange" ("min" . ,port) ("max" . ,port)))))
              ports))))

(define %egress-rules
  #((("protocol" . "all") ("destination" . "0.0.0.0/0"))))

(define (open-ports! security-list ports)
  (oracle-request 'iaas 'PUT (string-append "/securityLists/" security-list)
                  `(("ingressSecurityRules" . ,(ingress-rules ports))
                    ("egressSecurityRules" . ,%egress-rules))))

(define (observed-ports security-list)
  "Return the TCP ports that the rules of SECURITY-LIST open, sorted."
  (sort (filter-map (lambda (rule)
                      (and (equal? "6" (json-ref rule "protocol"))
                           (json-ref rule "tcpOptions" "destinationPortRange"
                                     "min")))
                    (json-list security-list "ingressSecurityRules"))
        <))

(define (create! path body)
  "POST BODY to PATH, then wait for what it made to be available."
  (let ((made (oracle-request 'iaas 'POST path body)))
    (wait-for-state 'iaas (string-append path "/" (json-ref made "id"))
                    '("AVAILABLE"))))

(define (delete! path)
  "Delete PATH, then wait for it to be gone."
  (oracle-delete 'iaas path)
  (wait-for-state 'iaas path '("TERMINATED")))

(define (delete-network outputs)
  (let ((ref (lambda (key) (assq-ref outputs key))))
    (when (ref 'subnet-id)
      (delete! (string-append "/subnets/" (ref 'subnet-id))))
    (when (ref 'internet-gateway-id)
      ;; The route to the gateway must go first.
      (unless-gone (lambda ()
                     (oracle-request 'iaas 'PUT
                                     (string-append "/routeTables/"
                                                    (ref 'route-table-id))
                                     '(("routeRules" . #())))))
      (delete! (string-append "/internetGateways/"
                              (ref 'internet-gateway-id))))
    (delete! (string-append "/vcns/" (ref 'vcn-id)))))

(define (create-network _ props)
  (let* ((compartment (assq-ref props 'compartment))
         (name (assq-ref props 'name))
         (vcn (create! "/vcns"
                       `(("compartmentId" . ,compartment)
                         ("cidrBlocks" . #(,(assq-ref props 'cidr)))
                         ("displayName" . ,name))))
         (outputs `((vcn-id . ,(json-ref vcn "id"))
                    (route-table-id . ,(json-ref vcn "defaultRouteTableId"))
                    (security-list-id
                     . ,(json-ref vcn "defaultSecurityListId")))))
    ;; If a later step fails, delete what was made rather than leave a
    ;; half-made network behind.
    (with-exception-handler
        (lambda (e)
          (false-if-exception (delete-network outputs))
          (raise-exception e))
      (lambda ()
        (let ((gateway (create! "/internetGateways"
                                `(("compartmentId" . ,compartment)
                                  ("vcnId" . ,(json-ref vcn "id"))
                                  ("isEnabled" . #t)
                                  ("displayName" . ,name)))))
          (set! outputs `((internet-gateway-id . ,(json-ref gateway "id"))
                          ,@outputs))
          (oracle-request 'iaas 'PUT
                          (string-append "/routeTables/"
                                         (json-ref vcn "defaultRouteTableId"))
                          `(("routeRules"
                             . #((("destination" . "0.0.0.0/0")
                                  ("destinationType" . "CIDR_BLOCK")
                                  ("networkEntityId"
                                   . ,(json-ref gateway "id")))))))
          (open-ports! (json-ref vcn "defaultSecurityListId")
                       (assq-ref props 'ports))
          (let ((subnet (create! "/subnets"
                                 `(("compartmentId" . ,compartment)
                                   ("vcnId" . ,(json-ref vcn "id"))
                                   ("cidrBlock" . ,(assq-ref props 'cidr))
                                   ("displayName" . ,name)))))
            `((id . ,(json-ref subnet "id"))
              (subnet-id . ,(json-ref subnet "id"))
              ,@outputs)))))))

(define (read-network outputs)
  (let ((vcn (oracle-get 'iaas (string-append "/vcns/"
                                              (assq-ref outputs 'vcn-id))))
        (subnet (oracle-get 'iaas (string-append "/subnets/"
                                                 (assq-ref outputs
                                                           'subnet-id)))))
    (and vcn subnet
         (not (member (json-ref vcn "lifecycleState")
                      '("TERMINATING" "TERMINATED")))
         (cons `((name . ,(json-ref vcn "displayName"))
                 (compartment . ,(json-ref vcn "compartmentId"))
                 (cidr . ,(match (json-list vcn "cidrBlocks")
                            ((cidr . _) cidr)
                            (() #f)))
                 (ports . ,(observed-ports
                            (oracle-request 'iaas 'GET
                                            (string-append
                                             "/securityLists/"
                                             (assq-ref outputs
                                                       'security-list-id))))))
               outputs))))

(define (update-network outputs old new)
  (unless (equal? (assq-ref old 'ports) (assq-ref new 'ports))
    (open-ports! (assq-ref outputs 'security-list-id) (assq-ref new 'ports)))
  (unless (equal? (assq-ref old 'name) (assq-ref new 'name))
    (for-each (match-lambda
                ((path . key)
                 (oracle-request 'iaas 'PUT
                                 (string-append path (assq-ref outputs key))
                                 `(("displayName" . ,(assq-ref new 'name))))))
              '(("/vcns/" . vcn-id)
                ("/internetGateways/" . internet-gateway-id)
                ("/subnets/" . subnet-id))))
  outputs)

(define network-provider
  (register-provider!
   (make-provider 'oracle-network
                  #:create create-network
                  #:read read-network
                  #:update update-network
                  #:delete delete-network
                  #:replace-on '(compartment cidr))))

(define* (oracle-network resource-name
                         #:key (cidr "10.0.0.0/16") (ports '(22)) name
                         (compartment (oracle-compartment)))
  "Declare a network, named after RESOURCE-NAME and the stage, or NAME,
covering the addresses of CIDR.  The machines given it get a public
address, reach the internet, and can be reached on the TCP PORTS by anyone.
Changing CIDR or COMPARTMENT replaces it."
  (ensure-resource network-provider resource-name
                   `((name . ,(or name (physical-name resource-name)))
                     (compartment . ,compartment)
                     (cidr . ,cidr)
                     (ports . ,(sort (delete-duplicates ports) <)))))
