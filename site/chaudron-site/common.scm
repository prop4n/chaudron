;;; What every page shares: the head of the document, the top bar, the
;;; footer, and the panels holding code.

(define-module (chaudron-site common)
  #:use-module (haunt artifact)
  #:use-module (haunt html)
  #:use-module (ice-9 match)
  #:use-module (syntax-highlight)
  #:use-module (syntax-highlight scheme)
  #:export (%repository
            %description
            scheme
            report
            pot
            header
            footer
            document
            page))

(define %repository "https://github.com/prop4n/chaudron")

(define %description
  "A Guile library to describe and deploy infrastructure as plain Scheme programs: Hetzner Cloud, Guix System, Cloudflare.")

(define (scheme text)
  "A block of Scheme TEXT, highlighted."
  `(pre (@ (class "code"))
        (code ,@(highlights->sxml (highlight lex-scheme text)))))

(define (report . lines)
  "LINES printed by chaudron, each after its \"chaudron:\" prefix."
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

(define* (header links #:key docs? action)
  "The bar at the top of every page, with LINKS, a list of (label . url),
and ACTION, a (label . url) shown as a button after them.  On documentation
pages (DOCS?), it has a search button and a menu button."
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
                     ,@(match action
                         ((label . url)
                          `((a (@ (class "nav-action") (href ,url)) ,label)))
                         (#f '()))
                     ,@(if docs?
                           '((button (@ (class "menu-button") (type "button")
                                        (aria-expanded "false")
                                        (aria-controls "docs-sidebar"))
                                     "Menu"))
                           '())))))

(define (footer)
  `(footer (@ (class "footer"))
           (div (@ (class "wrap footer-inner"))
                (img (@ (src "/assets/cauldron.png") (alt "")
                        (width "35") (height "35")))
                (p "chaudron is free software, under the "
                   (a (@ (href "https://www.gnu.org/licenses/gpl-3.0.html"))
                      "GNU GPL")
                   ", version 3 or later. This site is built with Haunt.")
                (a (@ (href ,%repository)) "Source"))))

(define %site "https://chaudron.dev")

(define* (document title description body
                   #:key (path "/") (stylesheets '("/assets/style.css"))
                   (scripts '()))
  "A whole HTML page titled TITLE, with BODY, a list of elements, served at
PATH.  Its title, description and image are what chat apps and social
networks show when a link to it is shared."
  `((doctype "html")
    (html (@ (lang "en"))
          (head
           (meta (@ (charset "utf-8")))
           (meta (@ (name "viewport")
                    (content "width=device-width, initial-scale=1")))
           (title ,title)
           (meta (@ (name "description") (content ,description)))
           (link (@ (rel "canonical") (href ,(string-append %site path))))
           (meta (@ (property "og:type") (content "website")))
           (meta (@ (property "og:site_name") (content "chaudron")))
           (meta (@ (property "og:title") (content ,title)))
           (meta (@ (property "og:description") (content ,description)))
           (meta (@ (property "og:url") (content ,(string-append %site path))))
           (meta (@ (property "og:image")
                    (content ,(string-append %site "/assets/og.png"))))
           (meta (@ (property "og:image:width") (content "1200")))
           (meta (@ (property "og:image:height") (content "630")))
           (meta (@ (property "og:image:alt")
                    (content "The chaudron cauldron, and: infrastructure as plain Guile programs.")))
           (meta (@ (name "twitter:card") (content "summary_large_image")))
           (meta (@ (name "theme-color") (content "#4db62e")))
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
