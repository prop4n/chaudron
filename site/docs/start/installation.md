title: Installation
order: 2
description: What chaudron needs, with Guix or without it.
---

chaudron is a library, not a program: you install what it needs, then tell
Guile where to find it.

## What it needs

- [Guile](https://www.gnu.org/software/guile/) 3.0
- [guile-json](https://github.com/aconchillo/guile-json)
- [guile-gnutls](https://gitlab.com/gnutls/guile), for HTTPS
- [guile-gcrypt](https://notabug.org/cwebber/guile-gcrypt), for Cloudflare
  Workers

Guix is the easiest way to get them, but it is not required.

## Getting the library

chaudron is not packaged yet. Clone it, the library is in `lib/`:

```sh
$ git clone https://github.com/prop4n/chaudron
```

## With Guix

`lib/manifest.scm` lists the dependencies. Open a shell with them:

```sh
$ guix shell -m chaudron/lib/manifest.scm
```

## Without Guix

Install Guile 3, guile-json, guile-gnutls and guile-gcrypt with your
distribution's package manager. Package names vary from one distribution to
another, and some may not package them all: then build them from their
sources.

> [!NOTE]
> chaudron itself has only been used on Guix so far. If it works, or does
> not, on your distribution, please say so.

## Running a deployment

Give Guile the path of the library with `-L`:

```sh
$ guile -L chaudron/lib deploy.scm
```

Or set it once in your shell:

```sh
$ export GUILE_LOAD_PATH=$HOME/src/chaudron/lib
$ guile deploy.scm
```

To check that everything is found:

```sh
$ guile -L chaudron/lib -c '(use-modules (chaudron)) (display "ok\n")'
```

## For Guix System on Hetzner

The [`hetzner-guix-system`](/docs/guix-system/) resource is the only one
that needs more, on the machine running chaudron:

- `guix`, to run `guix deploy`; Guix can be installed on any distribution,
  you do not need Guix System;
- `ssh` and `ssh-keyscan`;
- a Guix signing key, made once with `guix archive --generate-key`.
