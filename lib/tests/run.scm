;; Run every test file, each in its own Guile, and say which ones failed.
;; From lib/:
;;
;;   guile -L . tests/run.scm

(use-modules (ice-9 ftw)
             (srfi srfi-1))

(define (test-file? name)
  (and (string-suffix? ".scm" name)
       (not (member name '("run.scm" "fake-api.scm")))))

(define files
  (map (lambda (name) (string-append "tests/" name))
       (scandir "tests" test-file?)))

(define failed
  (remove (lambda (file)
            (format #t "~%~a~%" file)
            (zero? (system* "guile" "-L" "." file)))
          files))

(newline)
(if (null? failed)
    (format #t "All ~a test files passed.~%" (length files))
    (begin
      (format #t "Failed: ~{~a~^, ~}.~%" failed)
      (exit 1)))
