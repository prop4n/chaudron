;; The Guix revision the site is built with, so that it builds the same
;; everywhere:
;;
;;   guix time-machine -C channels.scm -- shell -m manifest.scm -- haunt build

(list (channel
       (name 'guix)
       (url "https://git.guix.gnu.org/guix.git")
       (branch "master")
       (commit "17a0213a82f2fb6b02a56f42752764da459bb7d2")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
