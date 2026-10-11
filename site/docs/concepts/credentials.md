title: Credentials
order: 7
description: Where tokens come from, and how to keep them out of the code.
---

Each provider reads its token from an environment variable:

| Provider | Variable |
|---|---|
| Hetzner Cloud | `HCLOUD_TOKEN` |
| Cloudflare | `CLOUDFLARE_API_TOKEN`, and `CLOUDFLARE_ACCOUNT_ID` if the token reaches several accounts |
| Livebox | `LIVEBOX_USERNAME`, `admin` by default, and `LIVEBOX_PASSWORD` |

## A .env file

`load-env-file` reads `NAME=VALUE` lines from a file, `.env` by default,
and sets the variables that are not set already: the environment takes
precedence.

```scheme
(load-env-file ".env")
```

```sh .env
HCLOUD_TOKEN=…
CLOUDFLARE_API_TOKEN=…
```

Keep this file out of version control. It does nothing if the file does not
exist.

## From anywhere else

`with-hetzner` and `with-cloudflare` give a token for the code inside them.
Since a deployment is a program, the token can come from anywhere: a
password manager, a secret store, a file. With
[pass](https://www.passwordstore.org/):

```scheme
(use-modules (ice-9 popen)
             (ice-9 textual-ports))

(define (pass name)
  (let* ((port (open-input-pipe (string-append "pass show " name)))
         (secret (string-trim-right (get-string-all port))))
    (close-pipe port)
    secret))

(with-hetzner (pass "hetzner")
  (with-stage "prod"
    ...))
```

## Permissions

Give tokens no more than they need:

- a Hetzner token belongs to one project: use a project per set of
  resources you want to keep apart;
- a Cloudflare token only needs **DNS: Edit**, on the zones chaudron
  manages, and **Workers Scripts: Edit** for Workers.
