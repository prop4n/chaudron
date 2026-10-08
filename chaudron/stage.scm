;;; Stages: run a program, converge every resource it declares, then delete
;;; the resources it no longer declares.

(define-module (chaudron stage)
  #:use-module (chaudron resource)
  #:use-module (chaudron state)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-26)
  #:export (current-stage
            stage-name
            call-with-stage
            with-stage
            ensure-resource
            destroy-stage))

(define-record-type <stage>
  (make-stage name entries seen)
  stage?
  (name stage-name)
  (entries stage-entries)                ;hash table: (kind . name) -> entry
  (seen stage-seen set-stage-seen!))     ;keys declared during this run

(define current-stage (make-parameter #f))

(define (entry-key entry)
  (cons (assq-ref entry 'kind) (assq-ref entry 'name)))

(define (load-stage name)
  (let ((entries (make-hash-table)))
    (for-each (lambda (entry) (hash-set! entries (entry-key entry) entry))
              (load-stage-state name))
    (make-stage name entries '())))

(define (stage-entry-list stage)
  (hash-map->list (lambda (key entry) entry) (stage-entries stage)))

(define (next-seq stage)
  (1+ (fold max 0 (map (cut assq-ref <> 'seq) (stage-entry-list stage)))))

;;; Converging one resource.

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

(define (converge provider name entry props)
  "Make resource NAME match PROPS and return its outputs."
  (let ((old-props (and entry (assq-ref entry 'props)))
        (outputs (and entry (assq-ref entry 'outputs))))
    (cond ((not entry)
           ((provider-create provider) name props))
          ((equal? old-props props)
           outputs)
          ((needs-replacement? provider old-props props)
           ((provider-delete provider) outputs)
           ((provider-create provider) name props))
          (else
           ((provider-update provider) outputs old-props props)))))

(define (ensure-resource provider name props)
  "Converge resource NAME, managed by PROVIDER, to PROPS within the current
stage.  Return the resulting <resource>."
  (let* ((stage (or (current-stage)
                    (error "resource declared outside of with-stage" name)))
         (kind (provider-kind provider))
         (key (cons kind name))
         (old (hash-ref (stage-entries stage) key))
         (props (resolve-references props)))
    (when (member key (stage-seen stage))
      (error "resource declared twice" kind name))
    (set-stage-seen! stage (cons key (stage-seen stage)))
    (let* ((outputs (converge provider name old props))
           (entry `((kind . ,kind)
                    (name . ,name)
                    (seq . ,(if old (assq-ref old 'seq) (next-seq stage)))
                    (props . ,props)
                    (outputs . ,outputs))))
      (unless (equal? entry old)
        (save-entry! (stage-name stage) entry)
        (hash-set! (stage-entries stage) key entry))
      (make-resource kind name props outputs))))

;;; Deleting resources.

(define (entry-provider entry)
  (or (lookup-provider (assq-ref entry 'kind))
      (error "no provider loaded for kind" (assq-ref entry 'kind))))

(define (destroy-entries! stage entries)
  "Delete ENTRIES, most recently created first."
  (let ((entries (sort entries (lambda (a b)
                                 (> (assq-ref a 'seq) (assq-ref b 'seq))))))
    (for-each entry-provider entries)   ;fail before deleting anything
    (for-each (lambda (entry)
                ((provider-delete (entry-provider entry))
                 (assq-ref entry 'outputs))
                (delete-entry! (stage-name stage)
                               (assq-ref entry 'kind) (assq-ref entry 'name))
                (hash-remove! (stage-entries stage) (entry-key entry)))
              entries)))

(define (orphans stage)
  (remove (lambda (entry) (member (entry-key entry) (stage-seen stage)))
          (stage-entry-list stage)))

(define (call-with-stage name thunk)
  "Call THUNK within stage NAME.  If it returns normally, delete the
resources of the stage it did not declare."
  (let ((stage (load-stage name)))
    (parameterize ((current-stage stage))
      (call-with-values thunk
        (lambda results
          (destroy-entries! stage (orphans stage))
          (apply values results))))))

(define-syntax-rule (with-stage name body ...)
  (call-with-stage name (lambda () body ...)))

(define (destroy-stage name)
  "Delete every resource of stage NAME."
  (let ((stage (load-stage name)))
    (parameterize ((current-stage stage))
      (destroy-entries! stage (stage-entry-list stage)))))
