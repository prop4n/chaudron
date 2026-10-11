title: Installation
order: 2
description: How to get chaudron, with Guix, or on Debian and Ubuntu.
---

chaudron is a Guile library. It needs Guile 3 and three libraries:
[guile-json](https://github.com/aconchillo/guile-json),
[guile-gnutls](https://gitlab.com/gnutls/guile), for HTTPS, and
[guile-gcrypt](https://notabug.org/cwebber/guile-gcrypt), for Cloudflare
Workers.

| System | Way |
|---|---|
| Guix, or any distribution with Guix installed | [the Guix channel](#with-guix) |
| Debian, Ubuntu | [apt](#on-debian-and-ubuntu) |

Elsewhere, install Guix first: it runs on any distribution.

## With Guix

The repository is a Guix channel. Add it to `~/.config/guix/channels.scm`:

```scheme ~/.config/guix/channels.scm
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

Its commits are signed: the introduction lets Guix check that what it
fetches comes from the channel's authors.

Then:

```sh
$ guix pull
$ guix install chaudron
$ guile deploy.scm
```

Or, without changing your channels, from a clone of the repository:

```sh
$ guix shell -f guix.scm guile -- guile deploy.scm
```

## On Debian and Ubuntu

Debian stable and Ubuntu 24.04 package everything chaudron needs:

```sh
$ sudo apt install guile-3.0 guile-json guile-gnutls guile-gcrypt
$ git clone https://github.com/prop4n/chaudron
$ guile -L chaudron/lib deploy.scm
```

In a minimal image, such as a container, add `netbase` and
`ca-certificates`: without them, HTTPS requests fail with
`Servname not supported for ai_socktype`.

To find the library without `-L`:

```sh
$ export GUILE_LOAD_PATH=$HOME/src/chaudron/lib
$ guile deploy.scm
```

## Checking it works

```sh
$ guile -c '(use-modules (chaudron)) (display "ok\n")'
```

Add `-L chaudron/lib` if the library is not installed.

## For Guix System on Hetzner

The [`hetzner-guix-system`](/docs/guix-system/) resource needs more, on the
machine running chaudron:

- `guix`, to run `guix deploy`; Guix can be installed on any distribution,
  you do not need Guix System;
- `ssh` and `ssh-keyscan`;
- a Guix signing key, made once with `guix archive --generate-key`.
