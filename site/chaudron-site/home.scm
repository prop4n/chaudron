;;; The home page.

(define-module (chaudron-site home)
  #:use-module (chaudron-site common)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (home))

(define (resources . names)
  `(ul (@ (class "resources"))
       ,@(map (lambda (name) `(li (code ,name))) names)))

(define %deploy-code "\
(use-modules (chaudron) (chaudron hetzner)
             (chaudron cloudflare))

(with-stage \"prod\"
  (define key
    (hetzner-ssh-key \"me\" #:public-key-file \"~/.ssh/id_ed25519.pub\"))

  ;; A server at Hetzner,
  (define server
    (hetzner-server \"web\" #:type \"cx23\" #:location \"fsn1\"
                    #:ssh-keys (list key)))

  ;; running the system of web-os.scm,
  (hetzner-guix-system \"web\" #:server server
                       #:os \"web-os.scm\" #:ssh-key key)

  ;; with its address at Cloudflare.
  (cloudflare-dns-record \"www\" #:zone \"example.com\"
                         #:content (output server 'ipv4)))")

(define %os-code "\
(use-modules (gnu) (gnu machine hetzner))
(use-service-modules web)

(define %base (make-hetzner-os \"cx23\"))

(operating-system
  (inherit %base)
  (host-name \"web\")
  (services
   (cons (service nginx-service-type
                  (nginx-configuration
                   (server-blocks
                    (list (nginx-server-configuration
                           (listen '(\"80\" \"[::]:80\"))
                           ;; public/, copied with the system.
                           (root (local-file \"public\" \"site\"
                                             #:recursive? #t)))))))
         (operating-system-user-services %base))))")

(define %page-code "\
<h1>Hello from chaudron!</h1>")

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

(define %project
  ;; The files of the example project, as tabs, and their content.
  `(("deploy.scm" (scheme ,%deploy-code))
    ("web-os.scm" (scheme ,%os-code))
    ("public/index.html" (text ,%page-code))))

(define (explorer)
  "The example project: a tab per file, the chosen file, and what the
program makes.  Radio buttons choose the file, without JavaScript."
  `(figure (@ (class "pot explorer"))
           ,@(map (lambda (n)
                    `(input (@ (type "radio") (name "file") (class "explorer-input")
                               (id ,(format #f "file-~a" n))
                               ,@(if (zero? n) '((checked "checked")) '()))))
                  (iota (length %project)))
           (div (@ (class "explorer-tabs") (role "tablist"))
                ,@(map (match-lambda*
                         (((path _) n)
                          `(label (@ (for ,(format #f "file-~a" n))
                                     (class "explorer-tab"))
                                  ,path)))
                       %project (iota (length %project))))
           (div (@ (class "explorer-panels"))
                ,@(map (match-lambda
                         ((_ content)
                          `(div (@ (class "explorer-panel"))
                                ,(match content
                                   (('scheme text) (scheme text))
                                   (('text text) `(pre (code ,text)))))))
                       %project))))

(define (diagram)
  "What deploy.scm makes, at which provider: drawn in HTML, the providers
as groups, the values passed between resources on the arrows."
  (define (box title detail)
    `(div (@ (class "diagram-box"))
          (span (@ (class "diagram-title")) ,title)
          (span (@ (class "diagram-detail")) ,detail)))
  (define (arrow label)
    `(div (@ (class "diagram-arrow")) (span ,label)))
  `(div (@ (class "diagram") (role "img")
           (aria-label "At Hetzner, web-os.scm is deployed to the server with guix deploy; the server's address goes to the DNS record at Cloudflare."))
        (div (@ (class "diagram-group"))
             (span (@ (class "diagram-group-name")) "Hetzner")
             ,(box "Guix System" "web-os.scm")
             ,(arrow "guix deploy")
             ,(box "server" "web, cx23"))
        ,(arrow "ipv4")
        (div (@ (class "diagram-group"))
             (span (@ (class "diagram-group-name")) "Cloudflare")
             ,(box "DNS record" "www.example.com"))))

(define %step-code "\
(with-stage \"dev\"
  (hetzner-server \"web\"
    #:type \"cx23\"
    #:location \"fsn1\"))")

(define (step number title text body)
  `(li (@ (class "step"))
       (div (@ (class "step-head"))
            (span (@ (class "step-number")) ,number)
            (h3 ,title))
       (p ,@text)
       ,body))

(define (hero)
  `(section (@ (class "hero"))
            ,(brew)
            (div (@ (class "wrap hero-grid"))
                 (div (@ (class "hero-text"))
                      (img (@ (class "hero-logo") (src "/assets/cauldron.png")
                              (alt "A pixel-art cauldron, bubbling green")
                              (width "96") (height "96")))
                      (h1 "Your infrastructure, written in Guile.")
                      (p (@ (class "lede"))
                         "Manage cloud servers, DNS records and whole operating "
                         "systems with ordinary Scheme code. No new "
                         "configuration language to learn.")
                      (div (@ (class "actions"))
                           (a (@ (class "button") (href "/docs/learn/"))
                              "Get started")
                           (a (@ (class "button button-quiet") (href "#example"))
                              "See how it works"))
                      (p (@ (class "hero-note"))
                         "New to Scheme or Guix? "
                         (a (@ (href "/docs/learn/"))
                            "Learn chaudron in 10 minutes")
                         ", with no cloud account."))
                 (ol (@ (class "steps-hero"))
                     ,(step "1" "Describe a server"
                            '("Resources are calls, in an environment called a stage.")
                            (pot "deploy.scm" (list (scheme %step-code))))
                     ,(step "2" "Run your program"
                            '("chaudron checks what exists, and creates or updates "
                              "what you described.")
                            (pot "shell"
                                 (list `(pre (code (span (@ (class "prompt")) "$ ")
                                                   "guile deploy.scm\n"
                                                   (span (@ (class "dim")) "chaudron: ")
                                                   "create hetzner-server/web")))))
                     ,(step "3" "Keep it in sync"
                            '("Run it again: nothing changes. Change "
                              (code "#:type") ", and the server is resized.")
                            (pot "shell"
                                 (list `(pre (code (span (@ (class "prompt")) "$ ")
                                                   "guile deploy.scm\n"
                                                   (span (@ (class "dim")) "chaudron: ")
                                                   "update hetzner-server/web (type)")))))))))

(define (example-section)
  `(section (@ (id "example") (class "band"))
            (div (@ (class "wrap example-grid"))
                 (div
                  (h2 "A real-world example")
                  (p "A server at Hetzner, the whole system that runs on it, "
                     "and its address at Cloudflare: two providers and an "
                     "operating system, in one program, with no glue code "
                     "between them.")
                  (p "Run once, about eight minutes later "
                     (code "www.example.com") " serves " (code "public/")
                     " from a fresh Guix System.")
                  (p (a (@ (href "/docs/static-site/")) "The whole recipe")))
                 (div (@ (class "hero-example"))
                      ,(explorer)
                      ,(diagram)))))

(define (points-section)
  `(section (@ (id "why") (class "band"))
            (div (@ (class "wrap"))
                 (h2 "One codebase for everything you deploy")
                 (ul (@ (class "points"))
                     (li (h3 "Providers talk to each other")
                         (p "A server's address goes to a DNS record, a "
                            "bucket's file becomes an image: outputs are "
                            "plain values, passed like any other."))
                     (li (h3 "The machines are code too")
                         (p "A Guix System is one declaration, deployed by "
                            (code "guix deploy") ". The same file gives the "
                            "same system, and each deployment can be rolled "
                            "back."))
                     (li (h3 "Procedures, not templates")
                         (p "A website, its server, its record and its system "
                            "fit in one procedure: two websites are two "
                            "calls. Loops and modules do the rest."))
                     (li (h3 "Everything pinned")
                         (p "The lock fixes Guix, chaudron and every package "
                            "on the servers: the same code gives the same "
                            "infrastructure, a year later.")))
                 (p (@ (class "more"))
                    (a (@ (href "/docs/why-scheme/"))
                       "Why Scheme, with a complete example")))))

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
                     (div (dt "Oracle Cloud")
                          (dd ,(resources "oracle-instance" "oracle-network"
                                          "oracle-bucket" "oracle-object"
                                          "oracle-image")))
                     (div (dt "Guix System")
                          (dd ,(resources "hetzner-guix-system"
                                          "oracle-guix-system")))
                     (div (dt "Cloudflare")
                          (dd ,(resources "cloudflare-dns-record"
                                          "cloudflare-worker"
                                          "cloudflare-kv-namespace"
                                          "cloudflare-d1-database")))
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
                  (p "With Guix, a project pins chaudron in its own "
                     (code "channels.scm") " and runs it with "
                     (code "guix time-machine") ": nothing to install. "
                     "On Debian and Ubuntu, apt has all it needs.")
                  (p (a (@ (href "/docs/installation/")) "Installation")
                     " · "
                     (a (@ (href "/docs/first-deployment/")) "Your first deployment"))
                  (p (@ (class "note"))
                     "chaudron is young: its interface may still change."))
                 ,(pot "shell"
                       (list `(pre (@ (class "shell"))
                                   (code
                                    (span (@ (class "prompt")) "$ ")
                                    "guix time-machine -C channels.scm -- \\\n"
                                    "    describe -f channels > channels.lock.scm\n"
                                    (span (@ (class "prompt")) "$ ")
                                    "guix time-machine -C channels.lock.scm -- \\\n"
                                    "    shell guile chaudron\n"
                                    (span (@ (class "prompt")) "$ ")
                                    "guile deploy.scm")))))))

(define (home site posts)
  (page "index.html"
        (document "chaudron: infrastructure as plain Guile programs"
                  %description
                  (list (header `(("How it works" . "#run")
                                  ("Providers" . "#providers")
                                  ("Source" . ,%repository))
                                #:action '("Docs" . "/docs/"))
                        `(main
                          ,(hero)
                          ,(example-section)
                          ,(points-section)
                          ,(run-section)
                          ,(open-section)
                          ,(providers-section)
                          ,(start-section))
                        (footer)))))
