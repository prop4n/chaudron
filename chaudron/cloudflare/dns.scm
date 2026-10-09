;;; Cloudflare DNS records.

(define-module (chaudron cloudflare dns)
  #:use-module (chaudron resource)
  #:use-module (chaudron stage)
  #:use-module (chaudron cloudflare api)
  #:export (cloudflare-dns-record))

(define (record-path outputs)
  (format #f "/zones/~a/dns_records/~a"
          (assq-ref outputs 'zone-id) (assq-ref outputs 'id)))

(define (record->json props)
  `(("type" . ,(assq-ref props 'type))
    ("name" . ,(assq-ref props 'name))
    ("content" . ,(assq-ref props 'content))
    ("ttl" . ,(assq-ref props 'ttl))
    ,@(if (member (assq-ref props 'type) '("A" "AAAA" "CNAME"))
          `(("proxied" . ,(assq-ref props 'proxied?)))
          '())
    ,@(if (assq-ref props 'priority)
          `(("priority" . ,(assq-ref props 'priority)))
          '())
    ;; Marks the records chaudron manages, as labels do at Hetzner.
    ("comment" . ,(string-append "chaudron: stage "
                                 (stage-name (current-stage))))))

(define (record-outputs zone-id record)
  `((id . ,(json-ref record "id"))
    (zone-id . ,zone-id)
    (name . ,(json-ref record "name"))))

(define (create-record _ props)
  (let ((zone-id (zone-id (assq-ref props 'zone))))
    (record-outputs zone-id
                    (cloudflare-request
                     'POST (format #f "/zones/~a/dns_records" zone-id)
                     (record->json props)))))

(define (read-record outputs)
  (and=> (cloudflare-get (record-path outputs))
         (lambda (record)
           (cons `((name . ,(json-ref record "name"))
                   (content . ,(json-ref record "content"))
                   (ttl . ,(json-ref record "ttl"))
                   (proxied? . ,(eq? #t (json-ref record "proxied"))))
                 outputs))))

(define (update-record outputs old new)
  (record-outputs (assq-ref outputs 'zone-id)
                  (cloudflare-request 'PUT (record-path outputs)
                                      (record->json new))))

(define (delete-record outputs)
  (cloudflare-delete (record-path outputs)))

(define dns-record-provider
  (register-provider!
   (make-provider 'cloudflare-dns-record
                  #:create create-record
                  #:read read-record
                  #:update update-record
                  #:delete delete-record
                  #:replace-on '(zone type))))

(define (full-name name zone)
  "Return NAME, relative to ZONE or \"@\" for ZONE itself, as a full name."
  (cond ((string=? name "@") zone)
        ((or (string=? name zone)
             (string-suffix? (string-append "." zone) name))
         name)
        (else (string-append name "." zone))))

(define* (cloudflare-dns-record resource-name
                                #:key zone (type 'A) content
                                (name resource-name) (ttl 1) proxied?
                                priority)
  "Declare a DNS record of TYPE, such as 'A, 'AAAA, 'CNAME, 'TXT or 'MX,
in ZONE, a domain managed by Cloudflare.  NAME is relative to ZONE, \"@\"
being ZONE itself.  A TTL of 1 means automatic; PROXIED? sends the traffic
of A, AAAA and CNAME records through Cloudflare; PRIORITY is for MX
records."
  (unless (and zone content)
    (error "cloudflare-dns-record: #:zone and #:content are required"
           resource-name))
  (ensure-resource dns-record-provider resource-name
                   `((zone . ,zone)
                     (type . ,(symbol->string type))
                     (name . ,(full-name name zone))
                     (content . ,content)
                     (ttl . ,ttl)
                     (proxied? . ,(and proxied? #t))
                     (priority . ,priority))))
