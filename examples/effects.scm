;; Handlers in plain Guile, without chaudron or Hetzner.
;;
;;   guile examples/effects.scm
;;
;; One program declares an infrastructure; several handlers run it in
;; different ways, without changing a line of it.

(use-modules (ice-9 exceptions)
             (ice-9 match))

;;; The effect: ask the current handler.  This would live in the library.

(define current-handler (make-parameter #f))

(define (resource kind name)
  "Ask the current handler for resource NAME of KIND."
  ((current-handler) kind name))

(define-syntax-rule (with-handler handler body ...)
  (parameterize ((current-handler handler))
    body ...))

;;; The program: plain code, unaware of how it is run.

(define (infra)
  (let* ((ip     (resource 'primary-ip "forge"))
         (data   (resource 'volume "data"))
         (server (resource 'server "forge")))
    (format #t "  => ~a, reachable at ~a, storing on ~a~%" server ip data)))

;;; Handlers: procedures from a kind and a name to an answer.

(define (for-real kind name)
  (format #t "  create ~a ~a~%" kind name)
  (match kind
    ('primary-ip "5.6.7.8")
    ('volume "/dev/sdb")
    ('server "server-42")))

(define (dry-run kind name)
  (format #t "  would create ~a ~a~%" kind name)
  (format #f "<~a ~a>" kind name))

(define (forbidding . kinds)
  "Return a handler that refuses KINDS and creates the rest for real."
  (lambda (kind name)
    (when (memq kind kinds)
      (raise-exception
       (make-exception-with-message
        (format #f "refusing to create ~a ~a" kind name))))
    (for-real kind name)))

(define (timed handler)
  "Return HANDLER, reporting how long each resource takes."
  (lambda (kind name)
    (let* ((start (get-internal-real-time))
           (answer (handler kind name)))
      (format #t "    (took ~ams)~%"
              (quotient (* 1000 (- (get-internal-real-time) start))
                        internal-time-units-per-second))
      answer)))

(define (declared program)
  "Return the resources PROGRAM declares, without creating any."
  (let ((resources '()))
    (with-output-to-string
      (lambda ()
        (with-handler (lambda (kind name)
                        (set! resources (cons (list kind name) resources))
                        #f)
          (program))))
    (reverse resources)))

;;; The same program, five ways.

(format #t "for real:~%")
(with-handler for-real (infra))

(format #t "~%dry run:~%")
(with-handler dry-run (infra))

(format #t "~%no servers allowed:~%")
(guard (e ((exception-with-message? e)
           (format #t "  stopped: ~a~%" (exception-message e))))
  (with-handler (forbidding 'server) (infra)))

(format #t "~%timed:~%")
(with-handler (timed for-real) (infra))

(format #t "~%declared:~%  ~s~%" (declared infra))
