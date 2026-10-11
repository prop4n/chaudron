title: Staging and production
order: 3
description: The same code for two environments, sharing one SSH key.
---

One procedure describes an environment; calling it with two stage names
makes two independent copies, of different sizes.

> [!NOTE]
> Tested on Hetzner Cloud.

## One SSH key per project

Hetzner accepts each SSH key only once per project. Declaring the same key
in two stages fails on the second:

```output
chaudron: could not create hetzner-ssh-key/me: SSH key not unique
```

So the key lives in a stage of its own, `"shared"`, and the environments
use its id.

## The program

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(load-env-file ".env")

;; Hetzner wants each SSH key once per project: it lives in its own stage,
;; shared by the others.
(define (shared)
  (with-stage "shared"
    (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub")))

(define* (environment stage #:key (servers 1) (type "cx23"))
  (let ((key (shared)))
    (with-stage stage
      (define ssh
        (hetzner-firewall "ssh" #:rules (list (allow-in 'tcp 22))))

      (map (lambda (n)
             (let ((server (hetzner-server (format #f "web-~a" n)
                                           #:type type
                                           #:location "fsn1"
                                           #:ssh-keys (list (output key 'id))
                                           #:firewalls (list ssh))))
               (output server 'ipv4)))
           (iota servers 1)))))

(match (command-line)
  ((_ "staging") (environment "staging"))
  ((_ "prod") (environment "prod" #:servers 2))
  ((_ "destroy" stage) (destroy-stage stage)))
```

- `with-stage` returns the value of its body: `(shared)` returns the key.
- The key is given by its id, with `output`: a resource cannot be given
  from one stage to another.

## Run it

```sh
$ guile -L chaudron/lib deploy.scm staging
```

```output
chaudron: create hetzner-ssh-key/me
chaudron: create hetzner-firewall/ssh
chaudron: create hetzner-server/web-1
```

```sh
$ guile -L chaudron/lib deploy.scm prod
```

```output
chaudron: create hetzner-firewall/ssh
chaudron: create hetzner-server/web-1
chaudron: create hetzner-server/web-2
```

At Hetzner, names carry their stage: `web-1-staging`, `web-1-prod`,
`web-2-prod`, `ssh-staging`, `ssh-prod`, and one key, `me-shared`.

## Clean up

Each stage is deleted on its own; destroying staging leaves production
alone:

```sh
$ guile -L chaudron/lib deploy.scm destroy staging
$ guile -L chaudron/lib deploy.scm destroy prod
$ guile -L chaudron/lib deploy.scm destroy shared
```
