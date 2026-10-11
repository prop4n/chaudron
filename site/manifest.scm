;; What building the site needs: Haunt, a Scheme highlighter, and the fonts,
;; which are subset to WOFF2 by fonttools.

(specifications->manifest
 '("guile"
   "haunt"
   "guile-syntax-highlight"
   "python-fonttools"
   "python-brotli"
   "font-atkinson-hyperlegible-next"
   "font-commit-mono"))
