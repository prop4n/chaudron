;;; The chaudron website, built with Haunt: the home page, and the
;;; documentation, written in Markdown under docs/.  The pieces are in
;;; chaudron-site/.
;;;
;;;   guix time-machine -C channels.scm -- shell -m manifest.scm -- haunt build
;;;
;;; The result is in public/.

(use-modules (haunt builder assets)
             (haunt reader commonmark)
             (haunt site)
             (chaudron-site docs)
             (chaudron-site fonts)
             (chaudron-site frames)
             (chaudron-site home))

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
