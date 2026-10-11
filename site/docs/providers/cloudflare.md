title: Cloudflare
order: 3
description: DNS records, and Workers serving static sites.
---

```scheme
(use-modules (chaudron) (chaudron cloudflare))
```

## Setup

Create an API token in the Cloudflare dashboard with the permissions of the
resources you use:

- **DNS: Edit**, on the zones chaudron manages, for DNS records;
- **Workers Scripts: Edit**, on the account, for Workers.

chaudron reads it from `CLOUDFLARE_API_TOKEN`, or from `with-cloudflare`:

```scheme
(with-cloudflare token
  (with-stage "prod" ...))
```

## Example

```scheme deploy.scm
(use-modules (chaudron) (chaudron hetzner) (chaudron cloudflare))

(with-stage "prod"
  (define forge (hetzner-server "forge" #:type "cx23" #:location "fsn1"))

  (cloudflare-dns-record "git"
                         #:zone "example.com"       ;git.example.com
                         #:content (output forge 'ipv4))

  (cloudflare-dns-record "apex" #:zone "example.com" #:name "@"
                         #:content (output forge 'ipv4)
                         #:proxied? #t)             ;through Cloudflare

  (cloudflare-dns-record "mail" #:zone "example.com" #:type 'MX
                         #:name "@" #:content "mx.example.com"
                         #:priority 10))
```

## cloudflare-dns-record

| Argument | Default | |
|---|---|---|
| `#:zone` | required | a domain managed by Cloudflare |
| `#:content` | required | the address, or the target |
| `#:type` | `'A` | `'AAAA`, `'CNAME`, `'TXT`, `'MX`… |
| `#:name` | the resource name | relative to the zone; `"@"` is the zone itself |
| `#:ttl` | `1` | in seconds; `1` means automatic |
| `#:proxied?` | `#f` | send the traffic through Cloudflare; for `A`, `AAAA` and `CNAME` |
| `#:priority` | none | for `MX` records |

Outputs: `id`, `zone-id`, `name`, the full name.

Changing a record's zone or type replaces it; anything else changes in
place.

Records managed by chaudron carry the comment `chaudron: stage <stage>`.
Unlike Hetzner resources, they are named as given, without the stage: two
stages declaring the same record fight over it.

## cloudflare-worker

A Worker serving a directory of static files, at a domain of yours or on
its `workers.dev` address. See the
[static site recipe](/docs/cloudflare-static-site/) for a complete example.

```scheme
(cloudflare-worker "site"
                   #:assets "public"
                   #:domain "www.example.com")
```

| Argument | Default | |
|---|---|---|
| `#:assets` | required | the directory of files to serve |
| `#:domain` | none | a host name in a zone managed by Cloudflare; without it, the Worker is served on `workers.dev` |
| `#:name` | the resource name and the stage | the Worker's name, such as `site-prod` |

Outputs: `name`, `url`.

- Whenever a file is added, removed or changed, the Worker is published
  again; only the files Cloudflare does not have yet are uploaded.
- Hidden files, whose name starts with a dot, are not served.
- `/docs/` serves `/docs/index.html`; a missing file is a 404.
- Changing the domain moves the Worker to the new one, in place. Changing
  its name replaces it.
- Deleting it deletes its domain too.

The Worker belongs to the account of the token. If the token reaches
several accounts, set `CLOUDFLARE_ACCOUNT_ID`, or use
`cloudflare-account-id`:

```scheme
(parameterize ((cloudflare-account-id "0123456789abcdef"))
  (with-stage "prod" ...))
```
