;;; Pixel frames around panels and buttons, drawn like the logo: an outline
;;; with rounded corners and a highlight along the top.  Each is an 11x11
;;; image that the style sheets slice into corners and edges.

(define-module (chaudron-site frames)
  #:use-module (haunt artifact)
  #:use-module (haunt html)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (frames))

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
    ("brew" "#04050a" "#84ef2e" "#c4f78f")
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
