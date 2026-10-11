;;; The chaudron website, built with Haunt: the home page, and the
;;; documentation, written in Markdown under docs/.
;;;
;;;   guix time-machine -C channels.scm -- shell -m manifest.scm -- haunt build
;;;
;;; The result is in public/.

(use-modules (haunt artifact)
             (haunt builder assets)
             (haunt html)
             (haunt post)
             (haunt reader commonmark)
             (haunt site)
             (ice-9 match)
             (ice-9 regex)
             (srfi srfi-1)
             (srfi srfi-11)
             (syntax-highlight)
             (syntax-highlight scheme))

(define %repository "https://github.com/prop4n/chaudron")

(define %description
  "A Guile library to describe and deploy infrastructure as plain Scheme programs: Hetzner Cloud, Guix System, Cloudflare.")

;;; Fonts, taken from the Guix profile and subset to what the page uses.

(define %fonts
  '(("opentype/AtkinsonHyperlegibleNext-Regular.otf" . "atkinson-regular.woff2")
    ("opentype/AtkinsonHyperlegibleNext-Bold.otf" . "atkinson-bold.woff2")
    ("opentype/AtkinsonHyperlegibleNext-ExtraBold.otf" . "atkinson-extrabold.woff2")
    ("truetype/CommitMono-400-Regular.ttf" . "commit-mono-regular.woff2")
    ("truetype/CommitMono-700-Regular.ttf" . "commit-mono-bold.woff2")))

(define %unicodes
  ;; Basic Latin, Latin-1, dashes, quotes, ellipsis, middle dot and arrows.
  "U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-201D,U+2026,U+2190-2193")

(define (font-file name)
  (string-append (or (getenv "GUIX_ENVIRONMENT")
                     (error "build the site from 'guix shell -m manifest.scm'"))
                 "/share/fonts/" name))

(define (fonts site posts)
  (map (match-lambda
         ((source . destination)
          (make-artifact (string-append "fonts/" destination)
                         (lambda (output)
                           (format #t "subset ~a~%" destination)
                           (unless (zero? (system* "pyftsubset" (font-file source)
                                                   (string-append "--output-file=" output)
                                                   "--flavor=woff2"
                                                   (string-append "--unicodes=" %unicodes)))
                             (error "could not subset" source))))))
       %fonts))

;;; Pixel frames around panels and buttons, drawn like the logo: an outline
;;; with rounded corners and a highlight along the top.  Each is an 11x11
;;; image that the style sheet slices into corners and edges.

(define %corner
  ;; The top-left corner, one character per pixel: o for the outline, h for
  ;; the highlight, f for the fill, and . for nothing.
  '("...oo"
    ".oohh"
    ".offf"
    "offff"
    "offff"))

(define (frame-rows)
  "Return the rows of a whole frame, mirroring the corner and repeating its
inner edges once."
  (define (row corner-row)
    (let ((edge (string-take-right corner-row 1)))
      (string-append corner-row edge (string-reverse corner-row))))
  (let* ((top (map row %corner))
         (middle (row (string-take-right (car (reverse %corner)) 5)))
         (bottom (map (lambda (line)
                        (string-map (lambda (c) (if (char=? c #\h) #\f c)) line))
                      (reverse top))))
    (append top (list middle) bottom)))

(define (frame-svg outline fill highlight)
  "Return the SVG of a frame drawn with OUTLINE, filled with FILL and lit
with HIGHLIGHT."
  (define (color c)
    (match c
      (#\o outline)
      (#\h highlight)
      (#\f fill)
      (#\. #f)))
  `(svg (@ (xmlns "http://www.w3.org/2000/svg")
           (width "11") (height "11") (viewBox "0 0 11 11")
           (shape-rendering "crispEdges"))
        ,@(append-map
           (lambda (line y)
             (filter-map (lambda (c x)
                           (and (color c)
                                `(rect (@ (x ,x) (y ,y) (width 1) (height 1)
                                          (fill ,(color c))))))
                         (string->list line)
                         (iota (string-length line))))
           (frame-rows)
           (iota 11))))

(define %frames
  ;; File name, outline, fill and highlight of each kind of frame.  On a dark
  ;; page, outlines are lighter than the page, or they would not show.
  '(("iron" "#04050a" "#1d1d2c" "#34344a")
    ("pale" "#04050a" "#e4e5ed" "#ffffff")
    ("note" "#04050a" "#e9eaf1" "#ffffff")
    ("caution" "#04050a" "#fbefd9" "#fffaf0")
    ("note-dark" "#40405a" "#1a1a27" "#2b2b3e")
    ("caution-dark" "#6b5a3a" "#2a2418" "#3d3420")
    ("iron-dark" "#40405a" "#1d1d2e" "#2e2e44")
    ("brew-dark" "#40405a" "#84ef2e" "#c4f78f")
    ("dusk-dark" "#40405a" "#2b2b3e" "#4a4a66")))

(define (frames site posts)
  (map (match-lambda
         ((name outline fill highlight)
          (serialized-artifact (string-append "assets/frames/" name ".svg")
                               (frame-svg outline fill highlight)
                               sxml->html)))
       %frames))

;;; Pieces of the page.

(define (scheme text)
  "A block of Scheme TEXT, highlighted."
  `(pre (@ (class "code"))
        (code ,@(highlights->sxml (highlight lex-scheme text)))))

(define (report . lines)
  "What chaudron prints on the error port: one LINES each."
  `(pre (@ (class "report"))
        (code ,@(map (lambda (line)
                       `(span (@ (class "line"))
                              (span (@ (class "prefix")) "chaudron:")
                              " " ,line "\n"))
                     lines))))

(define* (pot title body #:key (class ""))
  "A dark panel in a pixel frame, titled TITLE."
  `(figure (@ (class ,(string-append "pot " class)))
           (figcaption (@ (class "pot-title")) ,title)
           ,@body))

(define (resources . names)
  `(ul (@ (class "resources"))
       ,@(map (lambda (name) `(li (code ,name))) names)))

;;; The page.

(define %hero-code "\
(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare))

(with-stage \"prod\"
  (define forge
    (hetzner-server \"forge\" #:type \"cx23\"
                            #:location \"fsn1\"))

  (cloudflare-dns-record \"git\"
                         #:zone \"example.com\"
                         #:content (output forge 'ipv4)))")

(define %state-file "\
((kind . hetzner-volume)
 (name . \"data\")
 (seq . 4)
 (props (name . \"data-prod\")
        (size . 10)
        (location . \"fsn1\")
        (format . \"ext4\")
        (labels)
        (protected? . #f))
 (outputs
  (id . 104729301)
  (linux-device . \"/dev/disk/by-id/scsi-0HC_Volume_104729301\"))
 (depends-on))")

(define %guix-code "\
(hetzner-guix-system \"forge\"
                     #:server forge
                     #:os \"forge-os.scm\"
                     #:ssh-key key)")

(define %provider-code "\
(define thing-provider
  (register-provider!
   (make-provider 'acme-thing
                  #:create (lambda (name props) ...)
                  #:read   (lambda (outputs) ...)
                  #:update (lambda (outputs old new) ...)
                  #:delete (lambda (outputs) ...)
                  #:replace-on '(region))))")

(define* (header links #:key docs?)
  "The bar at the top of every page, with LINKS, a list of (label . url).
On documentation pages (DOCS?), it has a search button and a menu button."
  `(header (@ (class "masthead"))
           (div (@ (class "wrap masthead-inner"))
                (a (@ (class "brand") (href "/"))
                   (img (@ (src "/assets/cauldron.png") (alt "")
                           (width "35") (height "35")))
                   "chaudron"
                   ,@(if docs? '((span (@ (class "brand-docs")) "docs")) '()))
                (div (@ (class "masthead-end"))
                     ,@(if docs?
                           '((button (@ (class "search-button") (type "button"))
                                     "Search" (kbd "Ctrl K")))
                           '())
                     (nav (@ (aria-label "Main"))
                          ,@(map (match-lambda
                                   ((label . url) `(a (@ (href ,url)) ,label)))
                                 links))
                     ,@(if docs?
                           '((button (@ (class "menu-button") (type "button")
                                        (aria-expanded "false")
                                        (aria-controls "docs-sidebar"))
                                     "Menu"))
                           '())))))

(define %bubbles
  ;; Bubbles rising behind the hero: horizontal position in percent, size in
  ;; pixels of the logo, delay and duration in seconds.  Fixed, so that the
  ;; site builds the same every time.
  '((6 1 0 14) (14 2 5 18) (23 1 9 13) (31 1 2 16) (42 2 11 20)
    (48 1 6 15) (57 1 1 17) (64 2 8 19) (72 1 3 14) (81 1 10 16)
    (88 2 4 21) (95 1 7 15)))

(define (brew)
  "The background of the hero: a pixel dither, and bubbles rising."
  `(div (@ (class "brew") (aria-hidden "true"))
        ,@(map (match-lambda
                 ((x size delay duration)
                  `(span (@ (class ,(if (= size 2) "bubble bubble-big" "bubble"))
                            (style ,(format #f "left: ~a%; animation-delay: -~as; animation-duration: ~as"
                                            x delay duration))))))
               %bubbles)))

(define (hero)
  `(section (@ (class "hero"))
            ,(brew)
            (div (@ (class "wrap hero-grid"))
                 (div (@ (class "hero-text"))
                      (img (@ (class "hero-logo") (src "/assets/cauldron.png")
                              (alt "A pixel-art cauldron, bubbling green")
                              (width "210") (height "210")))
                      (h1 "Infrastructure as plain Guile programs.")
                      (p (@ (class "lede"))
                         "A deployment is a Scheme script. Each resource call "
                         "converges the real thing, a server, a DNS record, a "
                         "whole Guix System, and hands back its outputs. "
                         "No CLI, no plan to apply, no daemon.")
                      (div (@ (class "actions"))
                           (a (@ (class "button") (href "/docs/")) "Read the docs")
                           (a (@ (class "button button-quiet") (href ,%repository))
                              "Read the source")))
                 ,(pot "deploy.scm"
                       (list (scheme %hero-code)
                             `(div (@ (class "pot-run"))
                                   (span (@ (class "prompt")) "$ ")
                                   "guile -L . deploy.scm")
                             (report "create hetzner-server/forge"
                                     "create cloudflare-dns-record/git"))
                       #:class "hero-pot"))))

(define (run-section)
  `(section (@ (id "run") (class "band"))
            (div (@ (class "wrap"))
                 (h2 "What a run does")
                 (p (@ (class "intro"))
                    "Running the script is the deployment. A stage is one "
                    "environment, like " (code "\"prod\"") ", and its body is "
                    "ordinary Guile: loops, procedures and modules all work.")
                 (ol (@ (class "steps"))
                     (li (h3 "Load the stage")
                         (p (code "with-stage") " reads what chaudron knows "
                            "about the stage from " (code ".chaudron/prod/")
                            ": one small file per resource."))
                     (li (h3 "Converge each call, in order")
                         (p "Each resource call looks at the real resource, "
                            "brings it back if it drifted, then creates, "
                            "updates or replaces it, and saves its state right "
                            "away. Wrap independent calls in "
                            (code "concurrently") " to run them in parallel."))
                     (li (h3 "Delete what is gone")
                         (p "When the body returns, resources the script no "
                            "longer declares are deleted, each before what it "
                            "depends on. If the body raised an error, nothing "
                            "is deleted."))))))

(define (open-section)
  `(section (@ (class "band"))
            (div (@ (class "wrap"))
                 (h2 "Nothing hidden")
                 (p (@ (class "intro"))
                    "Everything chaudron knows and does is plain text you can "
                    "read, diff and commit.")
                 (div (@ (class "specimens"))
                      (div (@ (class "specimen specimen-state"))
                           (h3 "The state is data")
                           (p "One s-expression per resource. It is read, "
                              "never evaluated.")
                           ,(pot ".chaudron/prod/hetzner-volume/data.scm"
                                 (list (scheme %state-file))))
                      (div (@ (class "specimen"))
                           (h3 "Dry runs say what would change")
                           (p "The same script with " (code "#:dry-run? #t")
                              " reads the real resources and changes nothing.")
                           ,(pot "dry run"
                                 (list (report "create hetzner-volume/data (dry run)"
                                               "update hetzner-server/forge (volumes) (dry run)"
                                               "delete hetzner-firewall/web (dry run)"))))
                      (div (@ (class "specimen"))
                           (h3 "Drift is reported, then fixed")
                           (p "A change made by hand in the console is undone "
                              "by the next run, out loud.")
                           ,(pot "drift"
                                 (list (report "hetzner-server/forge has drifted: type is \"cx33\", expected \"cx23\""
                                               "update hetzner-server/forge (type)"))))))))

(define (guix-section)
  `(section (@ (id "guix") (class "band"))
            (div (@ (class "wrap split"))
                 (div
                  (h2 "From a bare server to " (code "guix deploy"))
                  (p "Give " (code "hetzner-guix-system") " a server and an "
                     (code "operating-system") " file. The first run installs "
                     "Guix System on it; later runs deploy again whenever the "
                     "file, or the Guix you run, changes.")
                  (ol (@ (class "sequence"))
                      (li "Boots the server into Hetzner's rescue system.")
                      (li (strong "Erases its disk") " and installs a minimal "
                          "Guix System.")
                      (li "Deploys your configuration with "
                          (code "guix deploy") ".")))
                 ,(pot "deploy.scm" (list (scheme %guix-code))))))

(define (providers-section)
  `(section (@ (id "providers") (class "band"))
            (div (@ (class "wrap"))
                 (h2 "Providers")
                 (dl (@ (class "providers"))
                     (div (dt "Hetzner Cloud")
                          (dd ,(resources "hetzner-server" "hetzner-ssh-key"
                                          "hetzner-firewall" "hetzner-primary-ip"
                                          "hetzner-volume" "hetzner-network"
                                          "hetzner-load-balancer"
                                          "hetzner-snapshot")))
                     (div (dt "Guix System")
                          (dd ,(resources "hetzner-guix-system")))
                     (div (dt "Cloudflare")
                          (dd ,(resources "cloudflare-dns-record"
                                          "cloudflare-worker")))
                     (div (dt "Livebox " (span (@ (class "tag")) "experimental"))
                          (dd ,(resources "livebox-port-forward"
                                          "livebox-dhcp-lease"))))
                 (div (@ (class "split split-provider"))
                      (div
                       (h3 "Write your own")
                       (p "A provider is a module with four procedures, of "
                          "which only " (code "create") " and "
                          (code "delete") " are required. Props and outputs "
                          "are association lists. Without " (code "update")
                          ", any change replaces the resource."))
                      ,(pot "acme.scm" (list (scheme %provider-code)))))))

(define (start-section)
  `(section (@ (id "start") (class "band"))
            (div (@ (class "wrap split"))
                 (div
                  (h2 "Get started")
                  (p "chaudron needs Guile 3, guile-json, guile-gnutls and "
                     "guile-gcrypt. "
                     "Guix is the easiest way to get them, not a requirement. "
                     "Until chaudron is packaged, point Guile at the library.")
                  (p (a (@ (href "/docs/installation/")) "Installation")
                     " · "
                     (a (@ (href "/docs/first-deployment/")) "Your first deployment"))
                  (p (@ (class "note"))
                     "chaudron is young: its interface may still change."))
                 ,(pot "shell"
                       (list `(pre (@ (class "shell"))
                                   (code
                                    (span (@ (class "prompt")) "$ ")
                                    "git clone " ,%repository "\n"
                                    (span (@ (class "prompt")) "$ ")
                                    "guix shell -m chaudron/lib/manifest.scm\n"
                                    (span (@ (class "prompt")) "$ ")
                                    "HCLOUD_TOKEN=… guile -L chaudron/lib deploy.scm")))))))

(define (footer)
  `(footer (@ (class "footer"))
           (div (@ (class "wrap footer-inner"))
                (img (@ (src "/assets/cauldron.png") (alt "")
                        (width "35") (height "35")))
                (p "chaudron is written in Guile Scheme. This site is built "
                   "with Haunt.")
                (a (@ (href ,%repository)) "Source"))))

(define* (document title description body
                   #:key (stylesheets '("/assets/style.css")) (scripts '()))
  "A whole HTML page titled TITLE, with BODY, a list of elements."
  `((doctype "html")
    (html (@ (lang "en"))
          (head
           (meta (@ (charset "utf-8")))
           (meta (@ (name "viewport")
                    (content "width=device-width, initial-scale=1")))
           (title ,title)
           (meta (@ (name "description") (content ,description)))
           (link (@ (rel "icon") (type "image/png")
                    (href "/assets/cauldron.png")))
           (link (@ (rel "preload") (as "font") (type "font/woff2")
                    (href "/fonts/atkinson-regular.woff2") (crossorigin "")))
           ,@(map (lambda (href) `(link (@ (rel "stylesheet") (href ,href))))
                  stylesheets)
           ,@(map (lambda (src) `(script (@ (src ,src) (defer ""))))
                  scripts))
          (body ,@body))))

(define (page file sxml)
  (serialized-artifact file sxml sxml->html))

(define (home site posts)
  (page "index.html"
        (document "chaudron: infrastructure as plain Guile programs"
                  %description
                  (list (header `(("How it works" . "#run")
                                  ("Providers" . "#providers")
                                  ("Docs" . "/docs/")
                                  ("Source" . ,%repository)))
                        `(main
                          ,(hero)
                          ,(run-section)
                          ,(open-section)
                          ,(guix-section)
                          ,(providers-section)
                          ,(start-section))
                        (footer)))))

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
    ((_ ... section file)
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

;;; Turning what guile-commonmark makes into pages: anchors on headings,
;;; highlighted code in pixel frames, callouts and tables.

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
  "What chaudron prints: lines starting with \"chaudron:\" get its color."
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

;;; Documentation pages.

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
     ;; /docs/ leads to the first page.
     (page "docs/index.html"
           `((doctype "html")
             (html (@ (lang "en"))
                   (head (meta (@ (charset "utf-8")))
                         (title "chaudron docs")
                         (meta (@ (http-equiv "refresh")
                                  (content ,(string-append
                                             "0; url="
                                             (doc-url (car reading-order)))))))
                   (body (a (@ (href ,(doc-url (car reading-order))))
                            "Documentation")))))
     (map (lambda (post)
            (page (string-append "docs/" (doc-slug post) "/index.html")
                  (doc-page post groups reading-order)))
          reading-order))))

;;; Search: an index of every page, read by docs.js.

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

(site #:title "chaudron"
      #:domain "chaudron.dev"
      #:build-directory "public"
      #:posts-directory "docs"
      #:readers (list commonmark-reader)
      #:builders (list home
                       docs
                       search-index
                       fonts
                       frames
                       (static-directory "assets")))
