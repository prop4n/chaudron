;; Tests for the provider-agnostic core, using an in-memory fake provider.

(use-modules (chaudron)
             (ice-9 exceptions)
             (ice-9 match)
             (ice-9 threads)
             (srfi srfi-1)
             (srfi srfi-64))

(define calls '())

;; The fake provider may be called from several threads at once.
(define lock (make-mutex))

(define (record! . call)
  (set! calls (append calls (list call))))

(define next-id 0)

;; The "real" infrastructure: id -> size.
(define world (make-hash-table))

;; Ids of resources that refuse to be deleted, like protected ones.
(define protected '())

;; Whether creating a resource fails once it exists, before it is complete.
(define fail-after-creating? #f)

(define fake
  (make-provider 'fake-thing
                 #:create (lambda (name props)
                            (let ((id (with-mutex lock
                                        (set! next-id (1+ next-id))
                                        (record! 'create name)
                                        (hash-set! world next-id 0)
                                        next-id)))
                              ;; Like a server whose backups are enabled
                              ;; once it exists.
                              (created! `((id . ,id)) props '((size . 0)))
                              (when fail-after-creating?
                                (error "could not set the size" id))
                              (with-mutex lock
                                (hash-set! world id (assq-ref props 'size)))
                              `((id . ,id))))
                 #:read (lambda (outputs)
                          (with-mutex lock
                            (let ((size (hash-ref world (assq-ref outputs 'id))))
                              (and size (cons `((size . ,size)) outputs)))))
                 #:update (lambda (outputs old new)
                            (with-mutex lock
                              (record! 'update (assq-ref outputs 'id))
                              (hash-set! world (assq-ref outputs 'id)
                                         (assq-ref new 'size))
                              outputs))
                 #:delete (lambda (outputs)
                            (when (memv (assq-ref outputs 'id) protected)
                              (error "protected" (assq-ref outputs 'id)))
                            (with-mutex lock
                              (record! 'delete (assq-ref outputs 'id))
                              (hash-remove! world (assq-ref outputs 'id))))
                 #:replace-on '(zone)))

;; A provider whose creations take a while, to check they overlap.
(define slow
  (register-provider!
   (make-provider 'slow-thing
                  #:create (lambda (name props) (usleep 300000) '((id . 0)))
                  #:delete (const #t))))

(register-provider! fake)

(define* (fake-thing name #:key (size 1) (zone "a") (refs '()))
  (ensure-resource fake name `((size . ,size) (zone . ,zone) (refs . ,refs))))

(define log "")

(define-syntax-rule (quietly-run body ...)
  (parameterize ((current-error-port (%make-void-port "w")))
    body ...))

(define-syntax-rule (run-calls body ...)
  (begin
    (set! calls '())
    (set! log (call-with-output-string
                (lambda (port)
                  (parameterize ((current-error-port port))
                    body ...))))
    calls))

(test-begin "stage")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX"))
               (exit-on-failure? #f))

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
    (run-calls (destroy-stage "dev")))

  (test-equal "deletes resources before those they depend on, even older ones"
    '(server firewall)
    (let* ((server (with-stage "deps" (output (fake-thing "server") 'id)))
           ;; The firewall is created after the server, then given to it.
           (firewall (with-stage "deps"
                       (let ((firewall (fake-thing "firewall")))
                         (fake-thing "server" #:refs (list firewall))
                         (output firewall 'id)))))
      (map (lambda (call)
             (if (equal? call `(delete ,server)) 'server 'firewall))
           (run-calls (destroy-stage "deps")))))

  (test-equal "destroying stops at a resource that refuses to be deleted"
    '(deleted-b-only clear-message exits-in-scripts kept-a recreated-b-only)
    (let* ((ids (with-stage "locks"
                  (map (lambda (name) (output (fake-thing name) 'id))
                       '("a" "b"))))
           (a (car ids))
           (b (cadr ids)))
      (set! protected (list a))
      (let* ((destroyed (run-calls (false-if-exception (destroy-stage "locks"))))
             (failure (guard (e ((chaudron-error? e) (exception-message e)))
                        (destroy-stage "locks")))
             (error-port (open-output-string))
             (status (catch 'quit
                       (lambda ()
                         (parameterize ((current-error-port error-port)
                                        (exit-on-failure? #t))
                           (destroy-stage "locks")))
                       (lambda (key status) status)))
             (kept? (hash-ref world a))
             (applied (run-calls (with-stage "locks"
                                   (fake-thing "a") (fake-thing "b")))))
        (set! protected '())
        (list (and (equal? destroyed `((delete ,b))) 'deleted-b-only)
              (and (equal? failure
                           (format #f "could not delete fake-thing/a: \
protected ~a" a))
                   'clear-message)
              (and (eqv? status 1)
                   (string-contains (get-output-string error-port)
                                    "chaudron: could not delete fake-thing/a")
                   'exits-in-scripts)
              (and kept? 'kept-a)
              (and (equal? applied '((create "b"))) 'recreated-b-only)))))

  ;; Creations that fail half-way.

  (test-equal "keeps a resource whose creation fails once it exists"
    '((create "h"))
    (run-calls
     (set! fail-after-creating? #t)
     (false-if-exception (with-stage "half" (fake-thing "h" #:size 5)))
     (set! fail-after-creating? #f)))

  (test-equal "finishes creating it on the next run"
    '((update) 5)
    (let ((calls (run-calls (with-stage "half" (fake-thing "h" #:size 5)))))
      (list (map car calls) (hash-ref world next-id))))

  (test-equal "is then complete"
    '()
    (run-calls (with-stage "half" (fake-thing "h" #:size 5))))

  (test-equal "reports errors that come with no list of irritants"
    "could not create broken-thing/b: no matching pattern"
    (let ((broken (make-provider 'broken-thing
                                 ;; A failed match raises an error whose
                                 ;; irritants are #f.
                                 #:create (lambda (name props)
                                            (match #f ((x) x)))
                                 #:delete (const #t))))
      (guard (e ((chaudron-error? e) (exception-message e)))
        (quietly-run (with-stage "broken" (ensure-resource broken "b" '()))))))

  ;; Moving resources.

  (test-equal "moving a resource keeps the real one"
    '(() #t)
    (let* ((id (with-stage "moves" (output (fake-thing "old") 'id)))
           (calls (run-calls
                   (with-stage "moves"
                     (moved 'fake-thing "old" "new")
                     (unless (equal? (output (fake-thing "new") 'id) id)
                       (error "not the same resource"))))))
      (list calls (and (string-contains log "move fake-thing/old to fake-thing/new")
                       #t))))

  (test-equal "a move left in the code does nothing"
    '()
    (run-calls (with-stage "moves"
                 (moved 'fake-thing "old" "new")
                 (fake-thing "new"))))

  (test-equal "a moved resource is still deleted after those depending on it"
    '(user thing)
    (let* ((thing (with-stage "moves-deps" (output (fake-thing "thing") 'id))))
      (with-stage "moves-deps"
        (let ((thing (fake-thing "thing")))
          (fake-thing "user" #:refs (list thing))))
      (with-stage "moves-deps"
        (moved 'fake-thing "thing" "renamed")
        (let ((thing (fake-thing "renamed")))
          (fake-thing "user" #:refs (list thing))))
      (map (lambda (call)
             (if (equal? call `(delete ,thing)) 'thing 'user))
           (run-calls (destroy-stage "moves-deps")))))

  (test-equal "a dry run only says it would move"
    '((create "dry-new"))
    (begin
      (with-stage "moves-dry" (fake-thing "dry-old"))
      (run-calls (with-stage "moves-dry" #:dry-run? #t
                   (moved 'fake-thing "dry-old" "dry-new")
                   (fake-thing "dry-new")))
      (unless (string-contains log "move fake-thing/dry-old to fake-thing/dry-new (dry run)")
        (error "no report" log))
      ;; Nothing was saved: without the move, the old one is an orphan.
      (run-calls (with-stage "moves-dry"
                   (fake-thing "dry-old")
                   (fake-thing "dry-new")))))

  (test-assert "refuses to move onto an existing resource"
    (guard (e ((error? e) (string-contains (exception-message e) "move")))
      (with-stage "moves-clash"
        (fake-thing "a")
        (fake-thing "b"))
      (with-stage "moves-clash"
        (moved 'fake-thing "a" "b")
        (fake-thing "b"))
      #f))

  (test-assert "refuses to move onto a resource already declared"
    (guard (e ((error? e) (string-contains (exception-message e) "move")))
      (with-stage "moves-late"
        (fake-thing "x")
        (moved 'fake-thing "y" "x"))
      #f))

  ;; Dry runs.

  (test-equal "a dry run changes nothing"
    '()
    (run-calls (with-stage "plan" #:dry-run? #t (fake-thing "a"))))

  (test-assert "a dry run reports what it would do"
    (string-contains log "create fake-thing/a (dry run)"))

  (test-equal "a dry run saves nothing"
    '((create "a"))
    (run-calls (with-stage "plan" (fake-thing "a"))))

  (test-equal "a dry run does not update"
    '()
    (run-calls (with-stage "plan" #:dry-run? #t (fake-thing "a" #:size 3))))

  (test-assert "a dry run reports which props would change"
    (string-contains log "update fake-thing/a (size) (dry run)"))

  (test-equal "a dry run does not delete orphans"
    '()
    (run-calls (with-stage "plan" #:dry-run? #t #t)))

  (test-assert "a dry run reports the orphans it would delete"
    (string-contains log "delete fake-thing/a (dry run)"))

  (test-assert "outputs of resources not created yet are unknown"
    (begin
      (run-calls
       (with-stage "plan" #:dry-run? #t
         (fake-thing "a")
         (let ((b (fake-thing "b")))
           (fake-thing "c" #:refs (list b))
           (unless (unknown? (output b 'id))
             (error "known output" (output b 'id))))))
      #t))

  (test-equal "destroy-stage can be a dry run too"
    '()
    (begin
      (run-calls (destroy-stage "plan" #:dry-run? #t))
      (run-calls (with-stage "plan" (fake-thing "a")))))

  ;; Concurrency.

  (test-equal "concurrently returns the values in order"
    '(1 2 3)
    (call-with-values (lambda () (concurrently 1 (+ 1 1) 3)) list))

  (test-equal "creates resources concurrently"
    '("m1" "m2" "m3" "m4" "m5" "m6" "m7" "m8")
    (sort (map cadr
               (run-calls
                (with-stage "many"
                  (concurrently (fake-thing "m1") (fake-thing "m2")
                                (fake-thing "m3") (fake-thing "m4")
                                (fake-thing "m5") (fake-thing "m6")
                                (fake-thing "m7") (fake-thing "m8")))))
          string<?))

  (test-equal "saves every resource created concurrently"
    '()
    (run-calls
     (with-stage "many"
       (concurrently (fake-thing "m1") (fake-thing "m2")
                     (fake-thing "m3") (fake-thing "m4")
                     (fake-thing "m5") (fake-thing "m6")
                     (fake-thing "m7") (fake-thing "m8")))))

  (test-equal "a failing branch raises and deletes nothing"
    '(boom ())
    (list (guard (e ((error? e) (string->symbol (exception-message e))))
            (run-calls
             (with-stage "many"
               (concurrently (fake-thing "m1") (error "boom")))))
          calls))

  (test-assert "reports from several threads do not mix"
    (let ((lines (string-split
                  (string-trim-right
                   (call-with-output-string
                     (lambda (port)
                       (parameterize ((current-error-port port))
                         (apply call-concurrently
                                (map (lambda (i)
                                       (lambda ()
                                         (report "line ~a of the report" i)))
                                     (iota 50)))))))
                  #\newline)))
      (and (= 50 (length lines))
           (every (lambda (line)
                    (and (string-prefix? "chaudron: line " line)
                         (string-suffix? " of the report" line)))
                  lines))))

  (test-assert "runs branches at the same time"
    (let ((start (get-internal-real-time)))
      (run-calls
       (with-stage "slow"
         (concurrently (ensure-resource slow "s1" '())
                       (ensure-resource slow "s2" '())
                       (ensure-resource slow "s3" '())
                       (ensure-resource slow "s4" '()))))
      (< (- (get-internal-real-time) start)
         (* 0.8 internal-time-units-per-second)))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "stage")
(exit (zero? failures))
