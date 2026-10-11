;; The exact commits of the channels in channels.scm.  To move to newer ones:
;;
;;   guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm

(list (channel
       (name 'chaudron)
       (url "https://github.com/prop4n/chaudron")
       (branch "main")
       (commit "626295f063dba225c855ca673ab57d5217b9f25c")
       (introduction
        (make-channel-introduction
         "86088179a3b0db539f47047c2dfe12d1d62b353d"
         (openpgp-fingerprint
          "4707 DBF9 AD31 C133 DC3D  E410 822B CCA9 C126 8873"))))
      (channel
       (name 'guix)
       (url "https://git.guix.gnu.org/guix.git")
       (branch "master")
       (commit "2a11acef8c2f8eb70e6f18abaddf8e22459e6006")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))

