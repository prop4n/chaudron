title: Installation
order: 2
description: Set up a project with chaudron, with Guix, or on Debian and Ubuntu.
---

chaudron is a Guile library. A project using it is a directory with a
program, often `deploy.scm`, and the way to get chaudron for it.

## A project

Choose a file to see what it is for.

```project
@ deploy.scm | commit
The program: the resources to deploy, in plain Guile. Run it with `guile deploy.scm`.
~~~ scheme
(use-modules (chaudron)
             (chaudron hetzner))

(load-env-file ".env")

(with-stage "prod"
  (hetzner-server "web" #:type "cx23" #:location "fsn1"))
~~~
@ channels.scm | commit
With Guix: the channels the project uses, Guix and chaudron, by branch.
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
With Guix: the exact commits of those channels. Commit it, so that everyone gets the same versions; make it again to update.
~~~ sh
$ guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
~~~
@ manifest.scm | optional
With Guix: the packages of the shell, when the project needs more than Guile and chaudron, such as OpenSSH for Guix System. Then open the shell with `shell -m manifest.scm`.
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
What chaudron knows about the resources it made, one file per resource, written by each run. Commit it, or keep it somewhere safe: without it, chaudron would create everything again.
@ .chaudron/prod/hetzner-server/web.scm | commit
The state of one resource: the arguments it was converged to, and what Hetzner returned. It is read as data, never evaluated. See [State](/docs/state/).
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

## With Guix

Each project says which Guix and which chaudron it uses, in its own
`channels.scm`. Nothing is installed in your profile, and your Guix
configuration is left alone.

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

### Pin the versions

`channels.scm` names branches. Record the exact commits they point to, so
that the project gets the same versions everywhere, today and in a year:

```sh
$ guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
```

This fetches the latest Guix and chaudron. Right after a new Guix commit,
before its build farm has built it, Guix builds it itself: it can take a
while, once.

Commit `channels.scm` and `channels.lock.scm` with your program.

### Run your program

Open a shell with chaudron, at the pinned versions:

```sh
$ guix time-machine -C channels.lock.scm -- shell guile chaudron
```

In it, run your program as often as you like:

```sh
$ guile deploy.scm
```

The first time takes a few minutes, the time for Guix to fetch the
channels; then it is immediate. To run a single command instead:

```sh
$ guix time-machine -C channels.lock.scm -- shell guile chaudron -- guile deploy.scm
```

### Trust the channel

Guix warns that `channel 'chaudron' is not trusted`: by default, it only
trusts the channels of your own `guix pull`. The warning does not stop
anything. To say once, on your machine, that you trust chaudron, list it in
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

### Update

To move to newer versions of Guix and chaudron, record the commits again,
and commit the new `channels.lock.scm`: its diff shows what changed.

```sh
$ guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
```

## On Debian and Ubuntu

Debian stable and Ubuntu 24.04 package everything chaudron needs: Guile 3,
guile-json, guile-gnutls for HTTPS, and guile-gcrypt for Cloudflare
Workers.

```sh
$ sudo apt install guile-3.0 guile-json guile-gnutls guile-gcrypt
$ git clone https://github.com/prop4n/chaudron ~/src/chaudron
$ export GUILE_LOAD_PATH=~/src/chaudron/lib
$ guile deploy.scm
```

Put the `export` line in your shell's configuration to keep it. In a
minimal image, such as a container, add `netbase` and `ca-certificates`:
without them, HTTPS requests fail with
`Servname not supported for ai_socktype`.

## In the rest of the documentation

Programs are run with `guile deploy.scm`: in the shell opened by
`guix time-machine`, or with `GUILE_LOAD_PATH` set. Tokens are read from the
environment or from a `.env` file next to the program; see
[Credentials](/docs/credentials/).

## For Guix System on Hetzner

The [`hetzner-guix-system`](/docs/guix-system/) resource needs more, on the
machine running chaudron:

- `guix`, to run `guix deploy`; Guix can be installed on any distribution,
  you do not need Guix System;
- `ssh` and `ssh-keyscan`;
- a Guix signing key, made once with `guix archive --generate-key`.
