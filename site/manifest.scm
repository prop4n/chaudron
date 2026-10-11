;; What building and deploying the site needs: Haunt, a Scheme highlighter,
;; the fonts, subset to WOFF2 by fonttools, and chaudron.

(specifications->manifest
 '("guile"
   "haunt"
   "guile-syntax-highlight"
   "python-fonttools"
   "python-brotli"
   "font-atkinson-hyperlegible-next"
   "font-commit-mono"
   "chaudron"))
