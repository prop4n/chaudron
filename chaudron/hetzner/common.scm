;;; Helpers shared by Hetzner resources: paths, actions, labels, names and
;;; delete protection.

(define-module (chaudron hetzner common)
  #:use-module (chaudron stage)
  #:use-module (chaudron hetzner api)
  #:use-module (srfi srfi-1)
  #:export (resource-path
            resource-action
            list-prop
            sync-lists!
            sorted-labels
            labels->json
            observe-metadata
            update-metadata!
            observe-protection
            protect!
            update-protection!))

(define (resource-path collection id . rest)
  "Return the API path of resource ID in COLLECTION, such as \"servers\"."
  (apply string-append "/" collection "/" (number->string id) rest))

(define* (resource-action collection id action #:optional body)
  "Run ACTION on resource ID of COLLECTION, wait for it, and return the
response."
  (let ((response (hetzner-request
                   'POST (resource-path collection id "/actions/" action)
                   body)))
    (wait-for-actions response)
    response))

(define (list-prop props key)
  (or (assq-ref props key) '()))

(define (sync-lists! old new add! remove!)
  "Call REMOVE! on each element of OLD missing from NEW, then ADD! on each
element of NEW missing from OLD."
  (for-each remove! (lset-difference equal? old new))
  (for-each add! (lset-difference equal? new old)))

;;; Names and labels.

(define %stage-label "chaudron/stage")

(define (sorted-labels labels)
  "Sort LABELS, an alist of strings, so that they compare equal whatever
their order."
  (sort labels (lambda (a b) (string<? (car a) (car b)))))

(define (labels->json props)
  "Return the labels of PROPS, plus the label of the current stage."
  (cons (cons %stage-label (stage-name (current-stage)))
        (list-prop props 'labels)))

(define (observe-metadata json)
  "Return the name and user labels of JSON, a resource from the API."
  `((name . ,(json-ref json "name"))
    (labels . ,(sorted-labels
                (remove (lambda (label) (string=? (car label) %stage-label))
                        (or (json-ref json "labels") '()))))))

(define (update-metadata! collection id old new)
  (unless (and (equal? (assq-ref old 'name) (assq-ref new 'name))
               (equal? (assq-ref old 'labels) (assq-ref new 'labels)))
    (hetzner-request 'PUT (resource-path collection id)
                     `(("name" . ,(assq-ref new 'name))
                       ("labels" . ,(labels->json new))))))

;;; Delete protection.

(define (observe-protection json)
  `((protected? . ,(eq? #t (json-ref json "protection" "delete")))))

(define* (protect! collection id props #:key rebuild?)
  "Set the delete protection of resource ID to the 'protected? prop of PROPS,
and its rebuild protection too when REBUILD? is true."
  (let ((protected? (eq? #t (assq-ref props 'protected?))))
    (resource-action collection id "change_protection"
                     `(("delete" . ,protected?)
                       ,@(if rebuild? `(("rebuild" . ,protected?)) '())))))

(define* (update-protection! collection id old new #:key rebuild?)
  (unless (eq? (assq-ref old 'protected?) (assq-ref new 'protected?))
    (protect! collection id new #:rebuild? rebuild?)))
