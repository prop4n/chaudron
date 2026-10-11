title: Installation
order: 2
description: Create a project with chaudron, step by step.
---

chaudron is a Guile library: there is nothing to install globally. Each
project says which chaudron it uses, and runs with it. Here is how to
create one with Guix; [on Debian and Ubuntu](#on-debian-and-ubuntu), only
the way to get chaudron changes.

## Create a project

### 1. Make a directory

```sh
$ mkdir my-infra
$ cd my-infra
$ git init
```

### 2. Name the channels

Write `channels.scm`: the project uses Guix, and chaudron from its channel.

```scheme channels.scm
(cons (channel
       (name 'chaudron)
       (url "https://github.com/prop4n/chaudron")
       (branch "main")
       (introduction
        (make-channel-introduction
         "86088179a3b0db539f47047c2dfe12d1d62b353d"
         (openpgp-fingerprint
          "4707 DBF9 AD31 C133 DC3D  E410 822B CCA9 C126 8873"))))
      %default-channels)
```

The introduction lets Guix check that the commits it fetches are signed
by chaudron's authors.

### 3. Pin the versions

Record the exact commits of these channels, so that the project gets the
same versions everywhere, today and in a year:

```sh
$ guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
```

It takes a few minutes the first time. Right after a new Guix commit,
before its build farm has built it, Guix builds it itself: longer, once.

### 4. Write the program

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "prod" #:dry-run? dry-run?
    (hetzner-server "web" #:type "cx23" #:location "fsn1")))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "prod"))
  (_ (deploy #f)))
```

### 5. Run it

Open a shell with chaudron, at the pinned versions:

```sh
$ guix time-machine -C channels.lock.scm -- shell guile chaudron
```

In it, see what the program would do. A dry run of resources that do not
exist yet needs no account:

```sh
$ guile deploy.scm dry-run
```

```output
chaudron: create hetzner-server/web (dry run)
```

### 6. Add your tokens

To deploy for real, chaudron needs the token of each provider. Put them in
`.env`, and keep that file out of git:

```sh .env
HCLOUD_TOKEN=your-token
```

```sh
$ echo .env > .gitignore
$ guile deploy.scm
```

```output
chaudron: create hetzner-server/web
```

The server exists, and it costs money until `guile deploy.scm destroy`.
[Credentials](/docs/credentials/) says where to get each token.

### 7. Commit

```sh
$ git add channels.scm channels.lock.scm deploy.scm .gitignore .chaudron
$ git commit -m "Deploy a server"
```

`.chaudron/` is what chaudron knows about the resources it made: commit it,
or keep it somewhere safe. Without it, chaudron would create everything
again. See [State](/docs/state/).

## What you end up with

Choose a file to see what it is for.

```project
@ deploy.scm | commit
The program: the resources to deploy, in plain Guile.
~~~ scheme
(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "prod" #:dry-run? dry-run?
    (hetzner-server "web" #:type "cx23" #:location "fsn1")))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "prod"))
  (_ (deploy #f)))
~~~
@ channels.scm | commit
The channels the project uses, Guix and chaudron, by branch.
~~~ scheme
(cons (channel
       (name 'chaudron)
       (url "https://github.com/prop4n/chaudron")
       (branch "main")
       (introduction
        (make-channel-introduction
         "86088179a3b0db539f47047c2dfe12d1d62b353d"
         (openpgp-fingerprint
          "4707 DBF9 AD31 C133 DC3D  E410 822B CCA9 C126 8873"))))
      %default-channels)
~~~
@ channels.lock.scm | generated
The exact commits of those channels: everyone gets the same versions. Made again to update.
~~~ sh
$ guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
~~~
@ manifest.scm | optional
The packages of the shell, when the project needs more than Guile and chaudron, such as OpenSSH for Guix System. Then open the shell with `shell -m manifest.scm` instead of `shell guile chaudron`.
~~~ scheme
(specifications->manifest
 '("guile" "chaudron" "openssh"))
~~~
@ .env | secret
The tokens, read by `load-env-file`. Never commit it.
~~~ sh
HCLOUD_TOKEN=...
CLOUDFLARE_API_TOKEN=...
~~~
@ .gitignore | commit
Keeps `.env` out of git.
~~~
.env
~~~
@ .chaudron/ | commit
What chaudron knows about the resources it made, one file per resource, written by each run. Commit it, or keep it somewhere safe.
@ .chaudron/prod/hetzner-server/web.scm | commit
The state of one resource: the arguments it was converged to, and what Hetzner returned. Read as data, never evaluated.
~~~ scheme
((kind . hetzner-server)
 (name . "web")
 (seq . 1)
 (props (name . "web-prod")
        (type . "cx23")
        (location . "fsn1")
        (image . "debian-12")
        (ssh-keys)
        (firewalls)
        (volumes)
        (networks)
        (ipv4 . #f)
        (ipv6 . #f)
        (user-data . #f)
        (backups? . #f)
        (labels)
        (protected? . #f))
 (outputs
  (id . 104729388)
  (ipv4 . "203.0.113.7")
  (ipv6 . "2001:db8::/64")
  (private-ipv4 . #f)
  (ipv4-id . 98315740)
  (ipv6-id . 98315741))
 (depends-on))
~~~
```

## Every day

| To | Run |
|---|---|
| open the project's shell | `guix time-machine -C channels.lock.scm -- shell guile chaudron` |
| see what would change | `guile deploy.scm dry-run` |
| deploy | `guile deploy.scm` |
| delete everything | `guile deploy.scm destroy` |
| move to newer Guix and chaudron | `guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm` |

Outside the shell, add `guix time-machine -C channels.lock.scm -- shell
guile chaudron --` in front of a `guile` command to run it alone. After an
update, commit the new `channels.lock.scm`: its diff shows what changed.

## Trust the channel

Guix may warn that `channel 'chaudron' is not trusted`: by default, it only
trusts the channels of your own `guix pull`. The warning stops nothing. To
say once, on your machine, that you trust chaudron, list it in
`~/.config/guix/trusted-channels.scm`:

```scheme ~/.config/guix/trusted-channels.scm
(cons (channel
       (name 'chaudron)
       (url "https://github.com/prop4n/chaudron")
       (introduction
        (make-channel-introduction
         "86088179a3b0db539f47047c2dfe12d1d62b353d"
         (openpgp-fingerprint
          "4707 DBF9 AD31 C133 DC3D  E410 822B CCA9 C126 8873"))))
      %default-channels)
```

This file only says which channels you trust: chaudron is not added to
your `guix pull`. Once it exists, Guix trusts nothing else, so list in it
the other channels you use too.

## On Debian and Ubuntu

Debian stable and Ubuntu 24.04 package everything chaudron needs. Get the
library once, and tell Guile where it is:

```sh
$ sudo apt install guile-3.0 guile-json guile-gnutls guile-gcrypt
$ git clone https://github.com/prop4n/chaudron ~/src/chaudron
$ export GUILE_LOAD_PATH=~/src/chaudron/lib
```

Put the `export` line in your shell's configuration to keep it. Then
create the project as above, skipping steps 2 and 3, and the shell of step
5: `guile deploy.scm` works directly.

In a minimal image, such as a container, add `netbase` and
`ca-certificates`: without them, HTTPS requests fail with
`Servname not supported for ai_socktype`.

## For Guix System on Hetzner

The [`hetzner-guix-system`](/docs/guix-system/) resource needs more, on the
machine running chaudron:

- `guix`, to run `guix deploy`; Guix can be installed on any distribution,
  you do not need Guix System;
- `ssh` and `ssh-keyscan`;
- a Guix signing key, made once with `guix archive --generate-key`.
