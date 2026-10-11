;;; Stages: run a program, converge every resource it declares, then delete
;;; the resources it no longer declares.

(define-module (chaudron stage)
  #:use-module (chaudron converge)
  #:use-module (chaudron resource)
  #:use-module (chaudron state)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-26)
  #:export (current-stage
            stage-name
            call-with-stage
            with-stage
            ensure-resource
            created!
            destroy-stage
            exit-on-failure?)
  #:re-export (report
               chaudron-error?))

(define-record-type <stage>
  (make-stage name dry-run? entries seen lock)
  stage?
  (name stage-name)
  (dry-run? stage-dry-run?)
  (entries stage-entries)                ;hash table: (kind . name) -> entry
  (seen stage-seen set-stage-seen!)      ;keys declared during this run
  (lock stage-lock))                     ;guards ENTRIES, SEEN and the state

(define current-stage (make-parameter #f))

;; Whether a failed operation ends the program with a short message, rather
;; than raising a &chaudron-error: by default, in scripts but not at the REPL.
(define exit-on-failure? (make-parameter 'auto))

(define (call-with-failure-handling thunk)
  (if (match (exit-on-failure?)
        ('auto (batch-mode?))
        (exit? exit?))
      (guard (e ((chaudron-error? e)
                 (report "~a" (exception-message e))
                 (exit 1)))
        (thunk))
      (thunk)))

(define (entry-key entry)
  (cons (assq-ref entry 'kind) (assq-ref entry 'name)))

(define (resource-id kind name)
  (format #f "~a/~a" kind name))

(define (load-stage name dry-run?)
  (let ((entries (make-hash-table)))
    (for-each (lambda (entry) (hash-set! entries (entry-key entry) entry))
              (load-stage-state name))
    (make-stage name dry-run? entries '() (make-mutex))))

(define (stage-entry-list stage)
  (hash-map->list (lambda (key entry) entry) (stage-entries stage)))

(define (next-seq stage)
  (1+ (fold max 0 (map (cut assq-ref <> 'seq) (stage-entry-list stage)))))

;;; Declaring resources.

(define (save-resource! stage kind name props outputs depends-on)
  "Save the state of resource NAME of KIND, unless it is unchanged."
  (with-mutex (stage-lock stage)
    (let* ((key (cons kind name))
           (old (hash-ref (stage-entries stage) key))
           (entry `((kind . ,kind)
                    (name . ,name)
                    (seq . ,(if old (assq-ref old 'seq) (next-seq stage)))
                    (props . ,props)
                    (outputs . ,outputs)
                    (depends-on . ,depends-on))))
      (unless (equal? entry old)
        (save-entry! (stage-name stage) entry)
        (hash-set! (stage-entries stage) key entry)))))

;; While a provider creates a resource: called with its props and outputs to
;; save it right away.
(define %save-created (make-parameter #f))

(define* (created! outputs props #:optional (pending '()))
  "Tell chaudron that the resource being created exists, with OUTPUTS, but
is not complete: PENDING is an alist of the PROPS that do not hold yet, with
the values they have instead.  It is saved at once, so that if creating it
fails afterwards, the next run finds it and updates it from there."
  (match (%save-created)
    (#f #f)
    (save!
     (save! (map (match-lambda
                   ((key . value) (or (assq key pending) (cons key value))))
                 props)
            outputs))))

(define (ensure-resource provider name props)
  "Converge resource NAME, managed by PROVIDER, to PROPS within the current
stage.  Return the resulting <resource>.  This may be called from several
threads at once."
  (let* ((stage (or (current-stage)
                    (error "resource declared outside of with-stage" name)))
         (kind (provider-kind provider))
         (key (cons kind name))
         (id (resource-id kind name))
         (depends-on (dependencies props))
         (props (resolve-references props))
         (old (with-mutex (stage-lock stage)
                (when (member key (stage-seen stage))
                  (error "resource declared twice" kind name))
                (set-stage-seen! stage (cons key (stage-seen stage)))
                (hash-ref (stage-entries stage) key)))
         (current (and old (observe provider id (assq-ref old 'props)
                                    (assq-ref old 'outputs))))
         (save! (lambda (props outputs)
                  (unless (stage-dry-run? stage)
                    (save-resource! stage kind name props outputs
                                    depends-on))))
         (outputs (parameterize ((%save-created save!))
                    (converge (stage-dry-run? stage) provider id name
                              current props))))
    (save! props outputs)
    (make-resource kind name props outputs)))

;;; Deleting resources.

(define (entry-provider entry)
  (or (lookup-provider (assq-ref entry 'kind))
      (error "no provider loaded for kind" (assq-ref entry 'kind))))

(define (deletion-order entries)
  "Sort ENTRIES so that each comes before the ones it depends on, and
otherwise the most recently created first."
  (let loop ((pending (sort entries (lambda (a b)
                                      (> (assq-ref a 'seq) (assq-ref b 'seq)))))
             (ordered '()))
    (define (needed? entry)
      (any (lambda (other)
             (member (entry-key entry) (or (assq-ref other 'depends-on) '())))
           pending))
    (match pending
      (() (reverse ordered))
      ((first . _)
       (let ((next (or (find (negate needed?) pending) first)))
         (loop (delete next pending) (cons next ordered)))))))

(define (destroy-entries! stage entries)
  "Delete ENTRIES, each before the ones it depends on."
  (let ((entries (deletion-order entries)))
    (for-each entry-provider entries)   ;fail before deleting anything
    (for-each (lambda (entry)
                (let ((kind (assq-ref entry 'kind))
                      (name (assq-ref entry 'name)))
                  (perform (stage-dry-run? stage) "delete" (resource-id kind name)
                           (lambda ()
                             ((provider-delete (entry-provider entry))
                              (assq-ref entry 'outputs))
                             (delete-entry! (stage-name stage) kind name)
                             (hash-remove! (stage-entries stage)
                                           (entry-key entry))))))
              entries)))

(define (orphans stage)
  (remove (lambda (entry) (member (entry-key entry) (stage-seen stage)))
          (stage-entry-list stage)))

(define* (call-with-stage name thunk #:key dry-run?)
  "Call THUNK within stage NAME.  If it returns normally, delete the
resources of the stage it did not declare.  With DRY-RUN?, only report what
would be done."
  (call-with-failure-handling
   (lambda ()
     (let ((stage (load-stage name dry-run?)))
       (parameterize ((current-stage stage))
         (call-with-values thunk
           (lambda results
             (destroy-entries! stage (orphans stage))
             (apply values results))))))))

(define-syntax with-stage
  (syntax-rules ()
    ((_ name #:dry-run? dry-run? body ...)
     (call-with-stage name (lambda () body ...) #:dry-run? dry-run?))
    ((_ name body ...)
     (call-with-stage name (lambda () body ...)))))

(define* (destroy-stage name #:key dry-run?)
  "Delete every resource of stage NAME, or with DRY-RUN?, only report it."
  (call-with-failure-handling
   (lambda ()
     (let ((stage (load-stage name dry-run?)))
       (parameterize ((current-stage stage))
         (destroy-entries! stage (stage-entry-list stage)))))))
