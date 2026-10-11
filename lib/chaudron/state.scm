;;; Persistent state: one s-expression file per resource.
;;;
;;;   .chaudron/<stage>/<kind>/<name>.scm
;;;
;;; Files are data: they are only ever read with `read', never evaluated.

(define-module (chaudron state)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 pretty-print)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:export (state-directory
            load-stage-state
            save-entry!
            delete-entry!))

(define state-directory (make-parameter ".chaudron"))

(define (stage-directory stage)
  (string-append (state-directory) "/" stage))

(define (entry-file stage kind name)
  (string-append (stage-directory stage) "/" (symbol->string kind)
                 "/" name ".scm"))

(define (mkdir-p dir)
  (unless (file-exists? dir)
    (mkdir-p (dirname dir))
    (mkdir dir)))

(define (directory-files dir pred)
  (if (file-exists? dir)
      (map (cut string-append dir "/" <>) (scandir dir pred))
      '()))

(define (hidden? file)
  (string-prefix? "." file))

(define (load-stage-state stage)
  "Return the list of entries stored for STAGE."
  (append-map (lambda (kind-dir)
                (map (cut call-with-input-file <> read)
                     (directory-files kind-dir (cut string-suffix? ".scm" <>))))
              (directory-files (stage-directory stage) (negate hidden?))))

(define (save-entry! stage entry)
  "Atomically write ENTRY, an alist with at least 'kind and 'name."
  (let* ((file (entry-file stage (assq-ref entry 'kind) (assq-ref entry 'name)))
         (tmp (string-append file ".tmp")))
    (mkdir-p (dirname file))
    (call-with-output-file tmp (cut pretty-print entry <>))
    (rename-file tmp file)))

(define (delete-entry! stage kind name)
  (let ((file (entry-file stage kind name)))
    (when (file-exists? file)
      (delete-file file))))
