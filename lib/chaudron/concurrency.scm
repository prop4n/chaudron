;;; Evaluating several expressions at the same time.

(define-module (chaudron concurrency)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:export (call-concurrently
            concurrently))

(define (call-concurrently . thunks)
  "Call each of THUNKS in its own thread and return their values, in order.
If some of them raise an exception, wait for all of them to finish, then
raise the first exception."
  (let ((results
         (map join-thread
              (map (lambda (thunk)
                     ;; New threads see the parameters of this one, such as
                     ;; the current stage.
                     (call-with-new-thread
                      (lambda ()
                        (with-exception-handler
                            (lambda (exception) (list 'error exception))
                          (lambda () (list 'ok (thunk)))
                          #:unwind? #t))))
                   thunks))))
    (for-each (match-lambda
                (('error exception) (raise-exception exception))
                (_ #t))
              results)
    (apply values (map cadr results))))

(define-syntax-rule (concurrently expression ...)
  "Evaluate each EXPRESSION in its own thread; return their values in order."
  (call-concurrently (lambda () expression) ...))
