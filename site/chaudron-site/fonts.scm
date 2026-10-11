;;; Fonts, taken from the Guix profile and subset to what the site uses.

(define-module (chaudron-site fonts)
  #:use-module (haunt artifact)
  #:use-module (ice-9 match)
  #:export (fonts))

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
