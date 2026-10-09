;; Tests for Cloudflare DNS records, against a scripted fake API.

(use-modules (chaudron)
             (chaudron cloudflare)
             (chaudron resource)
             (ice-9 exceptions)
             (srfi srfi-26)
             (srfi srfi-64)
             (tests fake-api))

(define (fields json . keys)
  (map (cut assoc-ref json <>) keys))

;; A Hetzner server, as far as DNS records are concerned.
(define forge
  (make-resource 'hetzner-server "forge" '() '((id . 42) (ipv4 . "1.2.3.4"))))

(define* (git #:key (content (output forge 'ipv4)) proxied?)
  (quietly
   (lambda ()
     (with-stage "prod"
       (cloudflare-dns-record "git" #:zone "example.com" #:content content
                              #:proxied? proxied?)))))

(define* (record #:key (content "1.2.3.4") (proxied #f))
  `(("id" . "r1") ("name" . "git.example.com") ("type" . "A")
    ("content" . ,content) ("ttl" . 1) ("proxied" . ,proxied)))

(define zones
  (cloudflare-ok #((("id" . "z1") ("name" . "example.com")))))

(test-begin "cloudflare")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates a record pointing to a server"
    '("git.example.com"
      ((GET "/zones?name=example.com") (POST "/zones/z1/dns_records"))
      ("A" "git.example.com" "1.2.3.4" 1 #f))
    (with-api (zones (cloudflare-ok (record)))
      (list (output (git) 'name)
            (routes)
            (fields (body 1) "type" "name" "content" "ttl" "proxied"))))

  (test-equal "marks the record as managed by chaudron"
    "chaudron: stage prod"
    (assoc-ref (body 1) "comment"))

  (test-equal "only reads when nothing changed"
    '((GET "/zones/z1/dns_records/r1"))
    (with-api ((cloudflare-ok (record)))
      (git)
      (routes)))

  (test-equal "updates the record in place"
    '(((GET "/zones/z1/dns_records/r1") (PUT "/zones/z1/dns_records/r1"))
      ("5.6.7.8" #t))
    (with-api ((cloudflare-ok (record))
               (cloudflare-ok (record #:content "5.6.7.8" #:proxied #t)))
      (git #:content "5.6.7.8" #:proxied? #t)
      (list (routes) (fields (body 1) "content" "proxied"))))

  (test-equal "corrects a record changed behind its back"
    '((GET "/zones/z1/dns_records/r1") (PUT "/zones/z1/dns_records/r1"))
    (with-api ((cloudflare-ok (record #:content "6.6.6.6" #:proxied #t))
               (cloudflare-ok (record #:content "5.6.7.8" #:proxied #t)))
      (git #:content "5.6.7.8" #:proxied? #t)
      (routes)))

  (test-equal "recreates a record deleted behind its back"
    '((GET "/zones/z1/dns_records/r1")
      (GET "/zones?name=example.com") (POST "/zones/z1/dns_records"))
    (with-api ('(404 . (("success" . #f)
                        ("errors" . #((("code" . 81044)
                                       ("message" . "Record does not exist."))))))
               zones
               (cloudflare-ok (record #:content "5.6.7.8" #:proxied #t)))
      (git #:content "5.6.7.8" #:proxied? #t)
      (routes)))

  (test-equal "deletes records that are no longer declared"
    '((DELETE "/zones/z1/dns_records/r1"))
    (with-api ((cloudflare-ok '(("id" . "r1"))))
      (quietly (lambda () (with-stage "prod" #t)))
      (routes)))

  (test-equal "raises API errors"
    '(400 81053 "could not create cloudflare-dns-record/git: An A, AAAA, or \
CNAME record with that host already exists.")
    (with-api (zones
               '(400 . (("success" . #f)
                        ("errors"
                         . #((("code" . 81053)
                              ("message" . "An A, AAAA, or CNAME record with \
that host already exists.")))))))
      (guard (e ((cloudflare-error? e)
                 (list (cloudflare-error-status e)
                       (cloudflare-error-code e)
                       (exception-message e))))
        (git))))

  (test-equal "names are relative to the zone"
    '("example.com" "www.example.com" "mail.example.com")
    (with-api (zones (cloudflare-ok '(("id" . "a")))
               zones (cloudflare-ok '(("id" . "b")))
               zones (cloudflare-ok '(("id" . "c"))))
      (quietly
       (lambda ()
         (with-stage "names"
           (cloudflare-dns-record "apex" #:zone "example.com" #:name "@"
                                  #:content "1.2.3.4")
           (cloudflare-dns-record "www" #:zone "example.com"
                                  #:name "www.example.com" #:type 'CNAME
                                  #:content "example.com")
           (cloudflare-dns-record "mx" #:zone "example.com" #:name "mail"
                                  #:type 'MX #:content "mx.example.com"
                                  #:priority 10))))
      (map (lambda (n) (assoc-ref (body n) "name")) '(1 3 5))))

  (test-equal "only A, AAAA and CNAME records can be proxied; MX have a priority"
    '((#f 10) (#t #f))                  ;MX, then CNAME
    (map (lambda (n)
           (list (pair? (assoc "proxied" (body n)))
                 (assoc-ref (body n) "priority")))
         '(5 3))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "cloudflare")
(exit (zero? failures))
