;;; Running commands on this machine.

(define-module (chaudron command)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 textual-ports)
  #:export (run-command
            invoke
            call-with-temporary-file
            expand-home))

(define* (spawn program arguments #:key input capture?)
  "Run PROGRAM with ARGUMENTS, feeding it INPUT if it is a string.  Return
its exit status and, with CAPTURE?, its output; otherwise its output goes to
ours."
  (cond (input
         (let ((port (apply open-pipe* OPEN_WRITE program arguments)))
           (display input port)
           (values (status:exit-val (close-pipe port)) #f)))
        (capture?
         (let* ((port (apply open-pipe* OPEN_READ program arguments))
                (output (get-string-all port)))
           (values (status:exit-val (close-pipe port)) output)))
        (else
         (values (status:exit-val (apply system* program arguments)) #f))))

;; Procedure running external commands, like `spawn'.  Swapped in tests.
(define run-command (make-parameter spawn))

(define* (invoke program arguments #:key input capture?)
  "Like `spawn', but raise an error unless PROGRAM succeeds, and return only
its output."
  (receive (status output)
      ((run-command) program arguments #:input input #:capture? capture?)
    (unless (eqv? 0 status)
      (error "command failed" program status))
    output))

(define (call-with-temporary-file proc)
  "Call PROC with the name of a new temporary file and an output port to it,
then delete the file."
  (let* ((port (mkstemp "/tmp/chaudron-XXXXXX"))
         (file (port-filename port)))
    (dynamic-wind
      (const #t)
      (lambda () (proc file port))
      (lambda () (false-if-exception (delete-file file))))))

(define (expand-home file)
  (if (string-prefix? "~/" file)
      (string-append (getenv "HOME") (string-drop file 1))
      file))
