;;; Converging one resource: comparing what it is to what it should be,
;;; and acting on the difference.

(define-module (chaudron converge)
  #:use-module (chaudron resource)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1)
  #:export (report
            chaudron-error?
            perform
            resolve-references
            dependencies
            observe
            converge))

;; Ports are not thread-safe: serialize reports, one whole line at a time.
(define %report-lock (make-mutex))

(define (report message . args)
  "Tell the user what chaudron is doing, on the error port."
  (let ((line (apply format #f (string-append "chaudron: " message "~%")
                     args)))
    (with-mutex %report-lock
      (display line (current-error-port))
      (force-output (current-error-port)))))

(define &chaudron-error
  (make-exception-type '&chaudron-error &error '()))

(define make-chaudron-error (record-constructor &chaudron-error))
(define chaudron-error? (exception-predicate &chaudron-error))

(define (describe-exception exception)
  "Return the message of EXCEPTION, with its irritants."
  (let ((message (if (exception-with-message? exception)
                     (exception-message exception)
                     (format #f "~s" exception)))
        (irritants (if (exception-with-irritants? exception)
                       (exception-irritants exception)
                       '())))
    (cond ((null? irritants)
           message)
          ((string-index message #\~)  ;a format string, as Guile's own errors
           (or (false-if-exception (apply format #f message irritants))
               message))
          (else
           (string-join (cons (string-append message ":")
                              (map (lambda (irritant)
                                     (format #f "~a" irritant))
                                   irritants))
                        " ")))))

(define (call-with-failure-context verb id thunk)
  "Call THUNK.  If it raises an error, raise it again as a &chaudron-error
saying that VERB failed on ID; the original error is kept, so that its own
predicates still recognize it."
  (with-exception-handler
      (lambda (exception)
        (raise-exception
         (if (and (error? exception) (not (chaudron-error? exception)))
             (make-exception (make-chaudron-error)
                             (make-exception-with-message
                              (format #f "could not ~a ~a: ~a" verb id
                                      (describe-exception exception)))
                             exception)
             exception)))
    thunk
    #:unwind? #t))

(define* (perform dry-run? verb id action #:key (keys '()) planned)
  "Report that VERB, such as \"create\", applies to resource ID because of
props KEYS, then call ACTION and return its result.  With DRY-RUN?, return
PLANNED instead of calling ACTION."
  (report "~a ~a~a~a" verb id
          (if (null? keys) "" (format #f " ~a" keys))
          (if dry-run? " (dry run)" ""))
  (if dry-run?
      planned
      (call-with-failure-context verb id action)))

(define (resolve-references props)
  "Replace every resource found in PROPS by its 'id output."
  (cond ((resource? props) (output props 'id))
        ((pair? props) (cons (resolve-references (car props))
                             (resolve-references (cdr props))))
        (else props)))

(define (dependencies props)
  "Return the (kind . name) of every resource found in PROPS."
  (cond ((resource? props)
         (list (cons (resource-kind props) (resource-name props))))
        ((pair? props)
         (delete-duplicates (append (dependencies (car props))
                                    (dependencies (cdr props)))))
        (else '())))

(define (needs-replacement? provider old new)
  (or (not (provider-update provider))
      (any (lambda (key)
             (not (equal? (assq-ref old key) (assq-ref new key))))
           (provider-replace-on provider))))

(define (observe provider id props outputs)
  "Ask PROVIDER what resource ID really looks like.  Return its current
props and outputs as a pair, or #f if it no longer exists."
  (match (call-with-failure-context
          "read" id
          (lambda ()
            ((or (provider-read provider) (lambda _ (cons '() outputs)))
             outputs)))
    (#f
     (report "~a no longer exists" id)
     #f)
    ((observed . outputs)
     (cons (map (match-lambda
                  ((key . expected)
                   (match (assq key observed)
                     (#f (cons key expected))
                     ((_ . actual)
                      (unless (equal? actual expected)
                        (report "~a has drifted: ~a is ~s, expected ~s"
                                id key actual expected))
                      (cons key actual)))))
                props)
           outputs))))

(define (changed-keys old new)
  (filter-map (match-lambda
                ((key . value)
                 (and (not (equal? value (assq-ref old key))) key)))
              new))

(define (converge dry-run? provider id name current props)
  "Make resource NAME match PROPS and return its outputs, or #f if a dry run
\(DRY-RUN?) would create it.  CURRENT is what it looks like now, as returned by
`observe'."
  (match current
    (#f
     (perform dry-run? "create" id
              (lambda () ((provider-create provider) name props))))
    ((old . outputs)
     (cond ((equal? old props)
            outputs)
           ((needs-replacement? provider old props)
            (perform dry-run? "replace" id
                     (lambda ()
                       ((provider-delete provider) outputs)
                       ((provider-create provider) name props))
                     #:keys (changed-keys old props)))
           (else
            (perform dry-run? "update" id
                     (lambda ()
                       ((provider-update provider) outputs old props))
                     #:keys (changed-keys old props)
                     #:planned outputs))))))
