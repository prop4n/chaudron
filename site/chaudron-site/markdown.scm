;;; Turning what guile-commonmark makes into pages: anchors on headings,
;;; highlighted code in pixel frames, callouts and tables.

(define-module (chaudron-site markdown)
  #:use-module (chaudron-site common)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:export (sxml-text
            annotate-headings))

(define (sxml-text tree)
  "All the text in TREE, flattened."
  (match tree
    ((? string? text) text)
    (((? symbol? tag) . children)
     (if (eq? tag '@) "" (string-concatenate (map sxml-text children))))
    ((children ...) (string-concatenate (map sxml-text children)))
    (_ "")))

(define (slugify text)
  "\"Stages and state\" -> \"stages-and-state\""
  (string-join (string-tokenize (string-downcase text)
                                (char-set-intersection char-set:letter+digit
                                                       char-set:ascii))
               "-"))

(define (blank? x)
  (and (string? x) (string-null? (string-trim-both x))))

(define (output-lines text)
  "What chaudron prints, its \"chaudron:\" prefixes highlighted."
  `(pre (@ (class "report"))
        (code ,@(map (lambda (line)
                       (if (string-prefix? "chaudron:" line)
                           `(span (@ (class "line"))
                                  (span (@ (class "prefix")) "chaudron:")
                                  ,(string-drop line (string-length "chaudron:"))
                                  "\n")
                           `(span (@ (class "line")) ,line "\n")))
                     (string-split text #\newline)))))

(define (shell-lines text)
  "Commands, each after a \"$ \" prompt that is not copied."
  `(pre (@ (class "shell"))
        (code ,@(append-map (lambda (line)
                              (if (string-prefix? "$ " line)
                                  `((span (@ (class "prompt")) "$ ")
                                    ,(string-drop line 2) "\n")
                                  (list line "\n")))
                            (string-split text #\newline)))))

(define (code-block info text)
  "A block of code, in a frame titled with the file name given after its
language (```scheme deploy.scm), or else with the language."
  (let* ((text (string-trim-right text #\newline))
         (words (string-tokenize info))
         (language (if (null? words) "" (car words)))
         (title (if (> (length words) 1) (cadr words) language)))
    (pot title
         (list (match language
                 ("scheme" (scheme text))
                 ("output" (output-lines text))
                 ((or "sh" "shell") (shell-lines text))
                 (_ `(pre (code ,text))))))))

(define %callouts
  ;; Keyword, class and title of each kind of callout.
  '(("NOTE" "note" "Note")
    ("TIP" "note" "Tip")
    ("CAUTION" "caution" "Caution")
    ("WARNING" "caution" "Caution")
    ("DANGER" "caution" "Danger")))

(define %callout-regexp (make-regexp "^\\[!([A-Z]+)\\][ \t]*([^\n]*)\n?"))

(define (callout children)
  "If CHILDREN, the content of a quote, starts with [!NOTE] or the like,
return the callout it stands for, or else #f."
  (match (remove blank? children)
    ((('p . paragraph) . rest)
     ;; The parser splits "[!NOTE]" in several strings: join them first.
     (let-values (((strings others) (span string? paragraph)))
       (let* ((start (string-concatenate strings))
              (m (regexp-exec %callout-regexp start))
              (kind (and m (assoc (match:substring m 1) %callouts))))
         (match kind
           ((_ class default-title)
            (let* ((title (match:substring m 2))
                   (text (cons (match:suffix m) others)))
              `(aside (@ (class ,(string-append "callout callout-" class)))
                      (p (@ (class "callout-title"))
                         ,(if (string-null? title) default-title title))
                      ,@(if (every blank? text) '() (list (cons 'p text)))
                      ,@rest)))
           (_ #f)))))
    (_ #f)))

(define (table-rows children)
  "Split CHILDREN, the content of a paragraph, in rows of cells, at line
breaks and at |; return #f unless it looks like a table."
  (define (split-at char nodes)
    ;; Split NODES in groups, at each CHAR found in their strings.
    (let loop ((nodes nodes) (group '()) (groups '()))
      (match nodes
        (() (reverse (cons (reverse group) groups)))
        (((? string? text) . rest)
         (let split ((pieces (string-split text char))
                     (group group) (groups groups))
           (match pieces
             ((last) (loop rest (cons last group) groups))
             ((piece . more)
              (split more '() (cons (reverse (cons piece group)) groups))))))
        ((node . rest) (loop rest (cons node group) groups)))))
  (define (trim-cell cell)
    (remove (lambda (node) (and (string? node) (string-null? node)))
            (match cell
              (() '())
              (_ (let* ((cell (if (string? (car cell))
                                  (cons (string-trim (car cell)) (cdr cell))
                                  cell))
                        (end (last cell)))
                   (if (string? end)
                       (append (drop-right cell 1) (list (string-trim-right end)))
                       cell))))))
  (define (row line)
    (let ((cells (map trim-cell (split-at #\| line))))
      ;; Drop the empty cells before the first | and after the last one.
      (let* ((cells (if (and (pair? cells) (null? (car cells))) (cdr cells) cells))
             (cells (if (and (pair? cells) (null? (last cells)))
                        (drop-right cells 1)
                        cells)))
        cells)))
  (define (separator? cells)
    (every (match-lambda
             (((? string? text)) (string-match "^:?-+:?$" text))
             (_ #f))
           cells))
  (and (pair? children)
       (string? (car children))
       (string-prefix? "|" (string-trim (car children)))
       (let ((rows (map row (remove (lambda (line) (every blank? line))
                                    (split-at #\newline children)))))
         (and (>= (length rows) 2)
              (separator? (cadr rows))
              rows))))

(define (table rows)
  (match rows
    ((head _ . body)
     `(div (@ (class "table"))
           (table (thead (tr ,@(map (lambda (cell) `(th ,@cell)) head)))
                  (tbody ,@(map (lambda (row)
                                  `(tr ,@(map (lambda (cell) `(td ,@cell)) row)))
                                body)))))))

(define (transform tree)
  (match tree
    ;; Haunt's reader puts the language in an infostring attribute,
    ;; guile-commonmark alone in a class.
    (('pre ('code ('@ ('infostring (? string? info))) . text))
     (code-block info (string-concatenate text)))
    (('pre ('code ('@ ('class (? string? class))) . text))
     (code-block (if (string-prefix? "language-" class)
                     (string-drop class (string-length "language-"))
                     "")
                 (string-concatenate text)))
    (('pre ('code (? string? text) ...))
     (code-block "" (string-concatenate text)))
    (('blockquote . children)
     (match (callout children)
       (#f (cons 'blockquote (map transform children)))
       (('aside attributes . content)
        `(aside ,attributes ,@(map transform content)))))
    (('p . children)
     (match (table-rows children)
       (#f (cons 'p (map transform children)))
       (rows (table rows))))
    (((? symbol? tag) . children)
     (cons tag (map transform children)))
    (_ tree)))

(define (annotate-headings body)
  "Return BODY with ids and anchors on its headings, and the entries of its
table of contents, as (level id text)."
  (let loop ((body body) (out '()) (toc '()) (seen '()))
    (match body
      (()
       (values (reverse out) (reverse toc)))
      ((((and tag (or 'h2 'h3)) . children) . rest)
       (let* ((text (sxml-text children))
              (base (slugify text))
              (n (count (lambda (id) (string=? id base)) seen))
              (id (if (zero? n) base (format #f "~a-~a" base (+ n 1)))))
         (loop rest
               (cons `(,tag (@ (id ,id))
                            ,@children
                            (a (@ (class "anchor") (href ,(string-append "#" id))
                                  (aria-hidden "true"))
                               "#"))
                     out)
               (cons (list tag id text) toc)
               (cons base seen))))
      ((element . rest)
       (loop rest (cons (transform element) out) toc seen)))))
