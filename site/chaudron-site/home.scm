;;; The home page.

(define-module (chaudron-site home)
  #:use-module (chaudron-site common)
  #:use-module (ice-9 match)
  #:export (home))

(define (resources . names)
  `(ul (@ (class "resources"))
       ,@(map (lambda (name) `(li (code ,name))) names)))

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

(define %bubbles
  ;; Bubbles rising behind the hero: position in percent, size in pixels of
  ;; the logo, delay and duration in seconds.
  '((6 1 0 14) (14 2 5 18) (23 1 9 13) (31 1 2 16) (42 2 11 20)
    (48 1 6 15) (57 1 1 17) (64 2 8 19) (72 1 3 14) (81 1 10 16)
    (88 2 4 21) (95 1 7 15)))

(define (brew)
  "The background of the hero."
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
