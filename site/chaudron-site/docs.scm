;;; The documentation: one Markdown file per page, docs/<section>/<page>.md,
;;; starting with a title, an order within its section, and optionally a
;;; description:
;;;
;;;   title: Stages
;;;   order: 1
;;;   description: One environment, deployed by one program.
;;;   ---
;;;
;;; Each page is served at /docs/<page>/.

(define-module (chaudron-site docs)
  #:use-module (chaudron-site common)
  #:use-module (chaudron-site markdown)
  #:use-module (haunt artifact)
  #:use-module (haunt post)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:export (docs
            search-index))

(define %sections
  ;; The directories under docs/, and their titles in the sidebar, in order.
  '(("start" . "Start here")
    ("concepts" . "Concepts")
    ("providers" . "Providers")
    ("recipes" . "Recipes")
    ("extending" . "Extending")))

(define (doc-section post)
  "The directory of POST under docs/, such as \"concepts\"."
  (match (string-split (post-file-name post) #\/)
    ((_ ... section _)
     (unless (assoc section %sections)
       (error "documentation page outside of the known sections"
              (post-file-name post)))
     section)))

(define (doc-slug post)
  (basename (post-file-name post) ".md"))

(define (doc-url post)
  (string-append "/docs/" (doc-slug post) "/"))

(define (doc-order post)
  (or (and=> (post-ref post 'order) string->number) 1000))

(define (doc-groups posts)
  "Group POSTS by section, as ((title post ...) ...), in the sidebar order."
  (filter-map (match-lambda
                ((directory . title)
                 (match (sort (filter (lambda (post)
                                        (string=? (doc-section post) directory))
                                      posts)
                              (lambda (a b) (< (doc-order a) (doc-order b))))
                   (() #f)
                   (posts (cons title posts)))))
              %sections))

(define (toc-list entries)
  "The \"On this page\" list: the h2, each with its h3."
  (define (link id text)
    `(a (@ (href ,(string-append "#" id))) ,text))
  (define (items entries)
    (match entries
      (() '())
      ((('h2 id text) . rest)
       (let-values (((subs more) (span (match-lambda (('h3 . _) #t) (_ #f))
                                       rest)))
         (cons `(li ,(link id text)
                    ,@(if (null? subs)
                          '()
                          `((ul ,@(map (match-lambda
                                         ((_ id text) `(li ,(link id text))))
                                       subs)))))
               (items more))))
      (((_ id text) . rest)
       (cons `(li ,(link id text)) (items rest)))))
  `(ul ,@(items entries)))

(define (sidebar groups current)
  `(nav (@ (aria-label "Documentation"))
        ,@(map (match-lambda
                 ((title . posts)
                  `(section (@ (class "sidebar-group"))
                            (h2 ,title)
                            (ul ,@(map (lambda (post)
                                         `(li (a (@ (href ,(doc-url post))
                                                    ,@(if (eq? post current)
                                                          '((aria-current "page"))
                                                          '()))
                                                 ,(post-title post))))
                                       posts)))))
               groups)))

(define (around post posts)
  "The posts before and after POST in POSTS."
  (let loop ((posts posts) (before #f))
    (match posts
      (() (values #f #f))
      ((first . rest)
       (if (eq? first post)
           (values before (and (pair? rest) (car rest)))
           (loop rest first))))))

(define (pager previous next)
  (define (link post class label)
    `(a (@ (class ,(string-append "pager-link " class))
           (href ,(doc-url post)))
        (span (@ (class "pager-label")) ,label)
        (span (@ (class "pager-title")) ,(post-title post))))
  `(nav (@ (class "pager") (aria-label "Previous and next pages"))
        ,(if previous (link previous "pager-previous" "Previous") '(span))
        ,(if next (link next "pager-next" "Next") '(span))))

(define %search-dialog
  `(dialog (@ (class "search") (id "search") (aria-label "Search"))
           (div (@ (class "search-box"))
                (input (@ (id "search-input") (type "search")
                          (placeholder "Search the documentation")
                          (autocomplete "off") (spellcheck "false")))
                (ul (@ (id "search-results"))))))

(define (doc-page post groups reading-order)
  (let-values (((body toc) (annotate-headings (post-sxml post)))
               ((previous next) (around post reading-order)))
    (define section-title (assoc-ref %sections (doc-section post)))
    (define description (post-ref post 'description))
    (define has-toc? (>= (length toc) 2))
    (document (string-append (post-title post) " · chaudron")
              (or description %description)
              (list (header `(("Home" . "/")
                              ("Source" . ,%repository))
                            #:docs? #t)
                    `(div (@ (class "docs"))
                          (aside (@ (class "docs-sidebar") (id "docs-sidebar"))
                                 ,(sidebar groups post))
                          (main (@ (class "docs-main"))
                                (p (@ (class "docs-section")) ,section-title)
                                (h1 ,(post-title post))
                                ,@(if description
                                      `((p (@ (class "docs-lede")) ,description))
                                      '())
                                ,@(if has-toc?
                                      `((details (@ (class "toc-mobile"))
                                                 (summary "On this page")
                                                 ,(toc-list toc)))
                                      '())
                                (div (@ (class "prose")) ,@body)
                                ,(pager previous next))
                          ,@(if has-toc?
                                `((aside (@ (class "docs-toc"))
                                         (h2 "On this page")
                                         ,(toc-list toc)))
                                '()))
                    %search-dialog)
              #:stylesheets '("/assets/style.css" "/assets/docs.css")
              #:scripts '("/assets/docs.js"))))

(define (docs site posts)
  (let* ((groups (doc-groups posts))
         (reading-order (append-map cdr groups)))
    (cons
     ;; /docs/ is the first page itself, rather than a redirection to it.
     (page "docs/index.html"
           (doc-page (car reading-order) groups reading-order))
     (map (lambda (post)
            (page (string-append "docs/" (doc-slug post) "/index.html")
                  (doc-page post groups reading-order)))
          reading-order))))

(define (json-string text)
  (call-with-output-string
    (lambda (port)
      (write-char #\" port)
      (string-for-each (lambda (c)
                         (case c
                           ((#\") (display "\\\"" port))
                           ((#\\) (display "\\\\" port))
                           ((#\newline) (display "\\n" port))
                           (else (when (char>=? c #\space) (write-char c port)))))
                       text)
      (write-char #\" port))))

(define (search-index site posts)
  (define (entry post)
    (string-append
     "{\"title\":" (json-string (post-title post))
     ",\"url\":" (json-string (doc-url post))
     ",\"section\":" (json-string (assoc-ref %sections (doc-section post)))
     ",\"text\":" (json-string (string-join
                                 (string-tokenize (sxml-text (post-sxml post)))
                                 " "))
     "}"))
  (serialized-artifact "docs/search.json"
                       ;; Sorted, so that the site builds the same everywhere.
                       (string-append "[" (string-join
                                           (map entry
                                                (sort posts
                                                      (lambda (a b)
                                                        (string<? (doc-url a)
                                                                  (doc-url b)))))
                                           ",\n")
                                      "]")
                       (lambda (json port) (display json port))))
