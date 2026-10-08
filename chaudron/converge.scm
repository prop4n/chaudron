;;; Converging one resource: comparing what it is to what it should be,
;;; and acting on the difference.

(define-module (chaudron converge)
  #:use-module (chaudron resource)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (report
            perform
            resolve-references
            observe
            converge))

(define (report message . args)
  "Tell the user what chaudron is doing, on the error port."
  (apply format (current-error-port)
         (string-append "chaudron: " message "~%") args))

(define* (perform dry-run? verb id action #:key (keys '()) planned)
  "Report that VERB, such as \"create\", applies to resource ID because of
props KEYS, then call ACTION and return its result.  With DRY-RUN?, return
PLANNED instead of calling ACTION."
  (report "~a ~a~a~a" verb id
          (if (null? keys) "" (format #f " ~a" keys))
          (if dry-run? " (dry run)" ""))
  (if dry-run? planned (action)))

(define (resolve-references props)
  "Replace every resource found in PROPS by its 'id output."
  (cond ((resource? props) (output props 'id))
        ((pair? props) (cons (resolve-references (car props))
                             (resolve-references (cdr props))))
        (else props)))

(define (needs-replacement? provider old new)
  (or (not (provider-update provider))
      (any (lambda (key)
             (not (equal? (assq-ref old key) (assq-ref new key))))
           (provider-replace-on provider))))

(define (observe provider id props outputs)
  "Ask PROVIDER what resource ID really looks like.  Return its current
props and outputs as a pair, or #f if it no longer exists."
  (match ((or (provider-read provider) (lambda _ (cons '() outputs))) outputs)
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
