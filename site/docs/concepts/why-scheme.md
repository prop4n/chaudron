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

A procedure is a pattern. Here, `website` makes a server, points a DNS
record at it, and installs a Guix System serving the site. Two websites are
two calls, made at the same time with `concurrently`:

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare))

(load-env-file ".env")
(load "system.scm")

(define (website name key)
  "A server where Guix System serves NAME.example.com."
  (let ((server (hetzner-server name #:type "cx23" #:location "fsn1"
                                #:ssh-keys (list key))))
    (cloudflare-dns-record name #:zone "example.com"
                           #:content (output server 'ipv4))
    (hetzner-guix-system name
                         #:server server
                         #:os (write-system! name (string-append name ".example.com"))
                         #:ssh-key key)))

(with-stage "sites"
  (define key
    (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))
  (concurrently (website "blog" key)
                (website "shop" key)))
```

`system.scm` holds the system of a website, for a domain:

```scheme system.scm
(use-modules (ice-9 pretty-print))

(define (system-of domain)
  "A Guix system where nginx serves a page for DOMAIN."
  `((use-modules (gnu) (gnu machine hetzner))
    (use-service-modules web)

    (define %base (make-hetzner-os "cx23"))
    (define %page (plain-file "index.html" ,domain))

    (operating-system
      (inherit %base)
      (host-name "web")
      (services
       (cons (service nginx-service-type
                      (nginx-configuration
                       (server-blocks
                        (list (nginx-server-configuration
                               (server-name (list ,domain))
                               (listen '("80"))
                               (root (file-union "site"
                                       (list (list "index.html" %page)))))))))
             (operating-system-user-services %base))))))

(define (write-system! name domain)
  "Write the system of DOMAIN to NAME-os.scm, and return that file."
  (let ((file (string-append name "-os.scm")))
    (call-with-output-file file
      (lambda (port)
        (for-each (lambda (form) (pretty-print form port) (newline port))
                  (system-of domain))))
    file))
```

## Code is data

`system-of` does not fill a text template: it returns the declaration of
the system, a Scheme expression, with the domain put in place by the
quasiquote, `` ` `` and `,`. `write-system!` writes it to `blog-os.scm` and
`shop-os.scm`, the files [`hetzner-guix-system`](/docs/guix-system/)
deploys. The domain, written once, ends up in the DNS record and in nginx.

## Run it

```output
chaudron: create hetzner-ssh-key/me
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
```

The two websites are made at the same time, in about seven minutes. Running
the program again changes nothing.

> [!NOTE]
> Tested on Hetzner Cloud and Cloudflare, with two websites.

## Everything pinned

The project's `channels.lock.scm` fixes the versions of Guix and of
chaudron, and so of every package on the servers: nginx, the kernel,
everything. The same program gives the same infrastructure, and the same
systems, a year later. See [Installation](/docs/installation/).

## What it does not do yet

The system is written to a file that Guix loads: values known when the
program starts, such as the domain, can be put in it. Values only known
once a resource exists, such as a server's address, are not passed to the
system.
