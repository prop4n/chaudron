;;; Signing Oracle Cloud API requests with an RSA key, as Oracle asks:
;;; https://docs.oracle.com/iaas/Content/API/Concepts/signingrequests.htm

(define-module (chaudron oracle signing)
  #:use-module (gcrypt base64)
  #:use-module (gcrypt hash)
  #:use-module (gcrypt pk-crypto)
  #:use-module (ice-9 match)
  #:use-module (ice-9 textual-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:export (read-rsa-key
            rsa-sign
            signing-string
            authorization))

;;; Reading the key.  Oracle gives a PKCS#8 PEM file ("BEGIN PRIVATE KEY");
;;; "BEGIN RSA PRIVATE KEY" files, PKCS#1, are read too.

(define (pem->der text)
  "Return the bytes of the first PEM block of TEXT."
  (let* ((lines (string-split text #\newline))
         (body (cdr (or (find-tail (cut string-prefix? "-----BEGIN" <>) lines)
                        (error "not a PEM file")))))
    (base64-decode
     (string-concatenate
      (map string-trim-both
           (let loop ((lines body))
             (match lines
               (() (error "unterminated PEM block"))
               ((line . rest)
                (if (string-prefix? "-----END" line)
                    '()
                    (cons line (loop rest)))))))))))

(define (der-element bv start)
  "Read the DER element at START in BV; return its tag, and the start and
end of its content."
  (let* ((tag (bytevector-u8-ref bv start))
         (first (bytevector-u8-ref bv (+ start 1))))
    (if (< first #x80)
        (values tag (+ start 2) (+ start 2 first))
        (let* ((count (- first #x80))
               (length (let loop ((i 0) (length 0))
                         (if (= i count)
                             length
                             (loop (1+ i)
                                   (+ (* 256 length)
                                      (bytevector-u8-ref bv (+ start 2 i))))))))
          (values tag (+ start 2 count) (+ start 2 count length))))))

(define (der-sequence bv start end)
  "Return the elements of the DER sequence content from START to END, as
(tag start . end) lists."
  (let loop ((position start) (elements '()))
    (if (>= position end)
        (reverse elements)
        (call-with-values (lambda () (der-element bv position))
          (lambda (tag content-start content-end)
            (loop content-end
                  (cons (cons* tag content-start content-end) elements)))))))

(define (der-contents bv element)
  (match element
    ((_ start . end)
     (let ((bytes (make-bytevector (- end start))))
       (bytevector-copy! bv start bytes 0 (- end start))
       bytes))))

(define %integer #x02)
(define %octet-string #x04)
(define %sequence #x30)

(define (rsa-private-key bv start end)
  "Return the integers of the PKCS#1 RSAPrivateKey from START to END in BV,
as bytevectors: version, n, e, d, p, q, d mod p-1, d mod q-1, q^-1 mod p."
  (map (cut der-contents bv <>) (der-sequence bv start end)))

(define (read-rsa-key file)
  "Read the unencrypted RSA private key in FILE, a PEM file, and return it
as a libgcrypt key."
  (let* ((der (pem->der (call-with-input-file file get-string-all)))
         (integers
          (call-with-values (lambda () (der-element der 0))
            (lambda (tag start end)
              (unless (= tag %sequence)
                (error "not an RSA private key" file))
              (match (der-sequence der start end)
                ;; PKCS#8: version, algorithm, then the PKCS#1 key.
                ((_ (#x30 . _) (#x04 key-start . key-end) . _)
                 (call-with-values (lambda () (der-element der key-start))
                   (lambda (_ start end)
                     (rsa-private-key der start end))))
                ;; PKCS#1.
                (((#x02 . _) . _)
                 (rsa-private-key der start end))
                (_ (error "not an RSA private key" file)))))))
    (match integers
      ((_ n e d p q _ _ q-inverse)
       ;; libgcrypt wants p < q and u = p^-1 mod q: give it OpenSSL's q
       ;; as p, and the other way round.
       (sexp->canonical-sexp
        `(private-key (rsa (n ,n) (e ,e) (d ,d) (p ,q) (q ,p)
                           (u ,q-inverse))))))))

;;; Signing.

(define (key-size key)
  "Return the size in bytes of the modulus of KEY."
  (let ((n (canonical-sexp-nth-data (find-sexp-token key 'n) 1)))
    (if (zero? (bytevector-u8-ref n 0))
        (1- (bytevector-length n))
        (bytevector-length n))))

(define (left-pad bytes size)
  "Return BYTES preceded by zeros up to SIZE bytes."
  (let ((padded (make-bytevector size 0)))
    (bytevector-copy! bytes 0 padded (- size (bytevector-length bytes))
                      (bytevector-length bytes))
    padded))

(define (rsa-sign key text)
  "Sign TEXT with KEY using RSASSA-PKCS1-v1_5 and SHA-256; return the
signature in base64."
  (let* ((data (bytevector->hash-data (sha256 (string->utf8 text))
                                      #:key-type 'rsa))
         (signature (sign data key)))
    ;; libgcrypt drops the leading zeros of the signature; Oracle wants it
    ;; as long as the key.
    (base64-encode
     (left-pad (canonical-sexp-nth-data (find-sexp-token signature 's) 1)
               (key-size key)))))

(define (signing-string headers)
  "Return the string to sign for HEADERS, a list of (name . value) pairs."
  (string-join (map (match-lambda
                      ((name . value) (string-append name ": " value)))
                    headers)
               "\n"))

(define (authorization key key-id headers)
  "Return the Authorization header signing HEADERS, as for
`signing-string', with KEY, whose Oracle ID is KEY-ID."
  (string-append "Signature version=\"1\",keyId=\"" key-id "\","
                 "algorithm=\"rsa-sha256\","
                 "headers=\"" (string-join (map car headers) " ") "\","
                 "signature=\"" (rsa-sign key (signing-string headers)) "\""))
