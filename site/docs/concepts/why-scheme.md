title: Why Scheme
order: 0
description: One language for the cloud and for the machines, and what it allows.
---

Infrastructure usually takes two tools, and two languages: one to create
the servers and the DNS records, such as Terraform and its HCL, and another
to configure the machines, such as Ansible and its YAML. With chaudron and
Guix, both are Scheme, in the same program.

## The machines are declared too

With [Guix System](/docs/guix-system/), a server is not configured step by
step: its whole system, services, users, packages, is one declaration.
Deploying the same declaration gives the same system, every time, and each
deployment is a generation that can be rolled back.

So a program describes the server at Hetzner, its DNS record at Cloudflare,
and what runs on it, together, versioned together.

## Procedures, not templates

A procedure is a pattern. Here, `website` makes a server, opens its
firewall, points a DNS record at it, and installs a Guix System serving the
site over HTTPS. Two websites are two calls, made at the same time with
`concurrently`:

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare)
             (ice-9 match)
             (ice-9 pretty-print))

(load-env-file ".env")

(define %zone "example.com")

(define (system-of domain)
  "The Guix system of a website at DOMAIN: nginx serving one page over
HTTPS, with a certificate from Let's Encrypt."
  `((use-modules (gnu) (gnu machine hetzner) (guix gexp))
    (use-service-modules certbot web)

    (define %base (make-hetzner-os "cx23"))

    (operating-system
      (inherit %base)
      (host-name "web")
      (services
       (cons* (service nginx-service-type
                       (nginx-configuration
                        (server-blocks
                         (list (nginx-server-configuration
                                (server-name (list ,domain))
                                (listen '("443 ssl" "[::]:443 ssl"))
                                (ssl-certificate
                                 ,(string-append "/etc/certs/" domain "/fullchain.pem"))
                                (ssl-certificate-key
                                 ,(string-append "/etc/certs/" domain "/privkey.pem"))
                                (root (file-union "site"
                                        (list (list "index.html"
                                                    (plain-file "index.html"
                                                                ,(string-append "<h1>" domain "</h1>\n")))))))))))
              (service certbot-service-type
                       (certbot-configuration
                        (certificates
                         (list (certificate-configuration
                                (domains (list ,domain))
                                (deploy-hook
                                 (program-file "nginx-reload"
                                   (gexp (let ((pid (call-with-input-file "/var/run/nginx/pid" read)))
                                           (kill pid SIGHUP))))))))))
              (operating-system-user-services %base))))))

(define (write-system! name domain)
  "Write the system of NAME, at DOMAIN, to NAME-os.scm; return that file."
  (let ((file (string-append name "-os.scm")))
    (call-with-output-file file
      (lambda (port)
        (for-each (lambda (form) (pretty-print form port) (newline port))
                  (system-of domain))))
    file))

(define (website name key)
  "A server named NAME running Guix System, serving NAME.%zone over HTTPS."
  (let* ((domain (string-append name "." %zone))
         (web (hetzner-firewall name #:rules (list (allow-in 'tcp 22)
                                                   (allow-in 'tcp 80)
                                                   (allow-in 'tcp 443))))
         (server (hetzner-server name #:type "cx23" #:location "fsn1"
                                 #:ssh-keys (list key)
                                 #:firewalls (list web))))
    (cloudflare-dns-record name #:zone %zone #:content (output server 'ipv4))
    (hetzner-guix-system name
                         #:server server
                         #:os (write-system! name domain)
                         #:ssh-key key)
    (string-append "https://" domain "/")))

(define (deploy)
  (with-stage "sites"
    (define key
      (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))
    (for-each (lambda (url) (format #t "~a~%" url))
              (call-with-values
                  (lambda ()
                    (concurrently (website "blog" key)
                                  (website "shop" key)))
                list))))

(match (command-line)
  ((_ "destroy") (destroy-stage "sites"))
  (_ (deploy)))
```

## Code is data

`system-of` does not fill a text template: it returns the declaration of
the system, a Scheme expression, with the domain put in place by the
quasiquote, `` ` `` and `,`. `write-system!` writes it to a file, the one
[`hetzner-guix-system`](/docs/guix-system/) deploys. A value defined once in
the program, the domain, ends up in the DNS record, in nginx and in the
certificate.

The `gexp` form is what `#~` stands for in a Guix configuration: the
program writes it out in full, since it runs with chaudron, not with Guix.

## Run it

```output
chaudron: create hetzner-ssh-key/me
chaudron: create hetzner-firewall/blog
chaudron: create hetzner-firewall/shop
chaudron: create hetzner-server/blog
chaudron: create hetzner-server/shop
chaudron: create cloudflare-dns-record/blog
chaudron: create hetzner-guix-system/blog
chaudron: create cloudflare-dns-record/shop
chaudron: create hetzner-guix-system/shop
chaudron: 203.0.113.7: erasing its disk to install Guix System
chaudron: 203.0.113.8: erasing its disk to install Guix System
...
chaudron: 203.0.113.7: deploying blog-os.scm
chaudron: 203.0.113.8: deploying shop-os.scm
https://blog.example.com/
https://shop.example.com/
```

The lines of the two websites interleave: they are made at the same time.
Both servers are installed in about seven minutes; each site then answers
over HTTPS, with its own certificate. Running the program again changes
nothing.

> [!NOTE]
> Tested on Hetzner Cloud and Cloudflare, with two websites.

## Everything pinned

The project's `channels.lock.scm` fixes the versions of Guix and of
chaudron, and so of every package on the servers: nginx, certbot, the
kernel. The same program gives the same infrastructure, and the same
systems, a year later. See [Installation](/docs/installation/).

## What it does not do yet

The system is written to a file that Guix loads: values known when the
program starts, such as the domain, can be put in it. Values only known
once a resource exists, such as a server's address, are not passed to the
system.
