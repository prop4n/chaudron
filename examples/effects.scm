;; Effects and handlers in plain Guile, without chaudron or Hetzner.
;;
;;   guile examples/effects.scm
;;
;; One program declares an infrastructure; several handlers run it in
;; different ways, without changing a line of it.

(use-modules (ice-9 curried-definitions)  ;(define ((f a) b) ...)
             (ice-9 match))

;;; The effect.

;; A prompt tag marks where an effect is caught; think of it as the name of
;; the effect.
(define %resource (make-prompt-tag 'resource))

(define (resource kind name)
  "Ask whoever runs us for resource NAME of KIND, and return what they
answer.  We do not know, nor care, how they get it."
  (abort-to-prompt %resource kind name))

;;; The program: plain code that only performs effects.

(define (infra)
  (let* ((ip     (resource 'primary-ip "forge"))
         (data   (resource 'volume "data"))
         (server (resource 'server "forge")))
    (format #t "  => ~a, reachable at ~a, storing on ~a~%" server ip data)))

;;; Running a program with a handler.

(define (run program handler)
  "Run PROGRAM.  Each time it performs a `resource' effect, call HANDLER
with RESUME, the rest of the program, and the KIND and NAME asked for."
  (call-with-prompt %resource
    program
    (lambda (resume kind name)
      ;; RESUME is the paused rest of PROGRAM.  It may be called with the
      ;; answer, later, or never.  It must run under the handler as well,
      ;; to catch the effects that follow.
      (handler (lambda (value)
                 (run (lambda () (resume value)) handler))
               kind name))))

;;; Handlers.

;; 1. Apply: pretend to call Hetzner, and resume with the result.
(define (apply-handler resume kind name)
  (format #t "  create ~a ~a~%" kind name)
  (resume (match kind
            ('primary-ip "5.6.7.8")
            ('volume "/dev/sdb")
            ('server "server-42"))))

;; 2. Dry run: do nothing, resume with a placeholder.
(define (dry-run-handler resume kind name)
  (format #t "  would create ~a ~a~%" kind name)
  (resume (format #f "<~a ~a>" kind name)))

;; 3. Guard: refuse some kinds, by never resuming: the program stops there.
(define ((guard-handler forbidden) resume kind name)
  (if (memq kind forbidden)
      (format #t "  refusing to create ~a ~a: stopping here~%" kind name)
      (apply-handler resume kind name)))

;; 4. Record: silently collect what the program declares, without running
;; anything for real.  Useful in tests.
(define (record program)
  (let ((declared '()))
    (with-output-to-string
      (lambda ()
        (run program
             (lambda (resume kind name)
               (set! declared (cons (list kind name) declared))
               (resume #f)))))
    (reverse declared)))

;; 5. Trace: wrap another handler and time each resource.
(define ((trace-handler handler) resume kind name)
  (let ((start (get-internal-real-time)))
    (handler (lambda (value)
               (format #t "    (~a ~a took ~ams)~%" kind name
                       (quotient (- (get-internal-real-time) start)
                                 (quotient internal-time-units-per-second
                                           1000)))
               (resume value))
             kind name)))

;;; The same program, five ways.

(format #t "apply:~%")
(run infra apply-handler)

(format #t "~%dry run:~%")
(run infra dry-run-handler)

(format #t "~%guard, no servers allowed:~%")
(run infra (guard-handler '(server)))

(format #t "~%record:~%  ~s~%" (record infra))

(format #t "~%trace, around apply:~%")
(run infra (trace-handler apply-handler))
