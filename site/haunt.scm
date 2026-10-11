;;; The chaudron website: see README.md.

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
