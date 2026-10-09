;; Tests for reading .env files.

(use-modules (chaudron)
             (srfi srfi-64))

(define (env-file content)
  (let* ((port (mkstemp "/tmp/chaudron-env-XXXXXX"))
         (file (port-filename port)))
    (display content port)
    (close-port port)
    file))

(test-begin "env")

(unsetenv "CHAUDRON_TEST_A")
(unsetenv "CHAUDRON_TEST_B")
(unsetenv "CHAUDRON_TEST_C")
(unsetenv "CHAUDRON_TEST_D")
(setenv "CHAUDRON_TEST_SET" "from the environment")

(load-env-file
 (env-file "# Tokens
CHAUDRON_TEST_A=plain
export CHAUDRON_TEST_B = \"double quoted\"

CHAUDRON_TEST_C='single = quoted'
CHAUDRON_TEST_D=
CHAUDRON_TEST_SET=from the file
"))

(test-equal "reads plain values" "plain" (getenv "CHAUDRON_TEST_A"))
(test-equal "accepts export and quotes" "double quoted"
  (getenv "CHAUDRON_TEST_B"))
(test-equal "keeps = in values" "single = quoted" (getenv "CHAUDRON_TEST_C"))
(test-equal "reads empty values" "" (getenv "CHAUDRON_TEST_D"))
(test-equal "leaves variables already set alone" "from the environment"
  (getenv "CHAUDRON_TEST_SET"))

(test-assert "ignores missing files"
  (begin (load-env-file "/nonexistent/.env") #t))

(test-error "rejects lines it does not understand" #t
  (load-env-file (env-file "NOT A VARIABLE\n")))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "env")
(exit (zero? failures))
