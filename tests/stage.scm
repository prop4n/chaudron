;; Tests for the provider-agnostic core, using an in-memory fake provider.

(use-modules (chaudron)
             (ice-9 exceptions)
             (srfi srfi-64))

(define calls '())

(define (record! . call)
  (set! calls (append calls (list call))))

(define next-id 0)

;; The "real" infrastructure: id -> size.
(define world (make-hash-table))

(define fake
  (make-provider 'fake-thing
                 #:create (lambda (name props)
                            (set! next-id (1+ next-id))
                            (record! 'create name)
                            (hash-set! world next-id (assq-ref props 'size))
                            `((id . ,next-id)))
                 #:read (lambda (outputs)
                          (let ((size (hash-ref world (assq-ref outputs 'id))))
                            (and size (cons `((size . ,size)) outputs))))
                 #:update (lambda (outputs old new)
                            (record! 'update (assq-ref outputs 'id))
                            (hash-set! world (assq-ref outputs 'id)
                                       (assq-ref new 'size))
                            outputs)
                 #:delete (lambda (outputs)
                            (record! 'delete (assq-ref outputs 'id))
                            (hash-remove! world (assq-ref outputs 'id)))
                 #:replace-on '(zone)))

(register-provider! fake)

(define* (fake-thing name #:key (size 1) (zone "a") (refs '()))
  (ensure-resource fake name `((size . ,size) (zone . ,zone) (refs . ,refs))))

(define log "")

(define-syntax-rule (run-calls body ...)
  (begin
    (set! calls '())
    (set! log (call-with-output-string
                (lambda (port)
                  (parameterize ((current-error-port port))
                    body ...))))
    calls))

(test-begin "stage")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates a new resource"
    '((create "a"))
    (run-calls (with-stage "dev" (fake-thing "a"))))

  (test-equal "does nothing when props are unchanged"
    '()
    (run-calls (with-stage "dev" (fake-thing "a"))))

  (test-equal "updates in place"
    '((update 1))
    (run-calls (with-stage "dev" (fake-thing "a" #:size 2))))

  (test-equal "replaces when a replace-on prop changes"
    '((delete 1) (create "a"))
    (run-calls (with-stage "dev" (fake-thing "a" #:size 2 #:zone "b"))))

  (test-equal "resources passed as props become their id"
    '((size . 1) (zone . "a") (refs 2))
    (with-stage "dev"
      (let ((a (fake-thing "a" #:size 2 #:zone "b")))
        (resource-props (fake-thing "b" #:refs (list a))))))

  (test-equal "returns outputs"
    2
    (with-stage "dev"
      (let ((a (fake-thing "a" #:size 2 #:zone "b")))
        (fake-thing "b" #:refs (list a))
        (output a 'id))))

  (test-equal "deletes orphans, newest first"
    '((delete 3) (delete 2))
    (run-calls (with-stage "dev" #t)))

  (test-equal "keeps everything when the body fails"
    '((create "x"))
    (run-calls
     (with-stage "dev" (fake-thing "x"))
     (false-if-exception
      (with-stage "dev" (error "boom")))))

  (test-assert "rejects a resource declared twice"
    (guard (e ((error? e) #t))
      (with-stage "dev" (fake-thing "x") (fake-thing "x"))
      #f))

  (test-assert "refuses ensure-resource outside a stage"
    (guard (e ((error? e) #t))
      (fake-thing "y")
      #f))

  (test-equal "stages are isolated"
    '((create "x"))
    (run-calls (with-stage "prod" (fake-thing "x"))))

  (test-equal "recreates a resource deleted behind its back"
    '((create "x"))
    (begin
      (hash-remove! world 5)
      (run-calls (with-stage "prod" (fake-thing "x")))))

  (test-assert "reports the missing resource"
    (string-contains log "fake-thing/x no longer exists"))

  (test-equal "corrects drift"
    '((update 6))
    (begin
      (hash-set! world 6 9)
      (run-calls (with-stage "prod" (fake-thing "x")))))

  (test-assert "reports the drift"
    (string-contains log "fake-thing/x has drifted: size is 9, expected 1"))

  (test-equal "is back in sync after correcting drift"
    '()
    (run-calls (with-stage "prod" (fake-thing "x"))))

  (test-equal "destroy-stage deletes everything in the stage"
    '((delete 4))
    (run-calls (destroy-stage "dev")))

  (test-equal "state survives across runs (no-op after destroy)"
    '()
    (run-calls (destroy-stage "dev"))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "stage")
(exit (zero? failures))
