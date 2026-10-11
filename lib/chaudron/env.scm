;;; Reading environment variables, such as API tokens, from .env files.

(define-module (chaudron env)
  #:use-module (ice-9 match)
  #:use-module (ice-9 rdelim)
  #:export (load-env-file))

(define (unquote-value value)
  (match (string->list value)
    (((and quote (or #\" #\')) chars ... last)
     (if (char=? quote last) (list->string chars) value))
    (_ value)))

(define (parse-line line)
  "Return the name and value of LINE, as \"NAME=VALUE\" or \"export
NAME=VALUE\", or #f for blank lines and comments."
  (let ((line (string-trim-both line)))
    (cond ((or (string-null? line) (string-prefix? "#" line))
          #f)
          ((string-index line #\=)
           => (lambda (index)
                (let ((name (string-trim-both
                             (let ((name (substring line 0 index)))
                               (if (string-prefix? "export " name)
                                   (string-drop name 7)
                                   name)))))
                  (when (or (string-null? name) (string-index name #\space))
                    (error "invalid line in .env file" line))
                  (cons name
                        (unquote-value
                         (string-trim-both (substring line (1+ index))))))))
          (else (error "invalid line in .env file" line)))))

(define* (load-env-file #:optional (file ".env"))
  "Set the environment variables defined in FILE, one NAME=VALUE per line,
unless they are already set: the environment overrides the file.  Do
nothing if FILE does not exist."
  (when (file-exists? file)
    (call-with-input-file file
      (lambda (port)
        (let loop ((line (read-line port)))
          (unless (eof-object? line)
            (match (parse-line line)
              ((name . value) (unless (getenv name) (setenv name value)))
              (#f #t))
            (loop (read-line port))))))))
