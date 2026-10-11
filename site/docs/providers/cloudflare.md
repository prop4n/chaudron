title: Cloudflare
order: 3
description: DNS records, Workers, KV namespaces and D1 databases.
---

```scheme
(use-modules (chaudron) (chaudron cloudflare))
```

## Setup

Create an API token in the Cloudflare dashboard with the permissions of the
resources you use:

- **DNS: Edit**, on the zones chaudron manages, for DNS records;
- **Workers Scripts: Edit**, on the account, for Workers;
- **Workers KV Storage: Edit**, on the account, for KV namespaces;
- **D1: Edit**, on the account, for D1 databases.

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

A Worker: code that Cloudflare runs close to visitors, files it serves, or
both, at a domain of yours or on its `workers.dev` address.

```scheme
(cloudflare-worker "api"
                   #:script "worker.js"
                   #:assets "public"
                   #:domain "www.example.com"
                   #:vars '(("GREETING" . "hello"))
                   #:secrets '("STRIPE_KEY")
                   #:bindings (list (kv-binding "VISITS" visits)
                                    (d1-binding "DB" hits))
                   #:crons '("*/30 * * * *"))
```

| Argument | Default | |
|---|---|---|
| `#:script` | none | a JavaScript module, the code of the Worker |
| `#:assets` | none | a directory of files to serve |
| `#:domain` | none | a host name in a zone managed by Cloudflare; without it, the Worker is served on `workers.dev` |
| `#:vars` | `'()` | variables given to the code, an association list of strings |
| `#:secrets` | `'()` | names of environment variables whose values are given to the code |
| `#:bindings` | `'()` | KV namespaces and D1 databases given to the code |
| `#:crons` | `'()` | when to run the code's `scheduled` handler |
| `#:name` | the resource name and the stage | the Worker's name, such as `api-prod` |

A Worker needs `#:script`, `#:assets`, or both. Outputs: `name`, `url`.

### The code

The script is an ES module. Its `fetch` handler answers requests; its
`scheduled` handler runs at the times of `#:crons`. Both receive `env`,
with the variables, secrets and bindings:

```js worker.js
export default {
  async fetch(request, env) {
    const visits = Number(await env.VISITS.get("count") ?? 0) + 1;
    await env.VISITS.put("count", String(visits));
    return Response.json({ greeting: env.GREETING, visits });
  },
  async scheduled(event, env) {
    await env.DB.prepare("DELETE FROM hits WHERE at < datetime('now', '-30 days')").run();
  }
};
```

With `#:assets` too, a request for an existing file gets the file, and any
other request goes to the code, which can also reach the files as
`env.ASSETS`.

### Secrets

`#:secrets` lists environment variables, such as those of `.env`: their
values are given to the code, encrypted by Cloudflare, and never written in
chaudron's state, which only keeps a digest of each to notice changes.
Each run that publishes the Worker needs them set.

### Bindings

`(kv-binding variable namespace)` and `(d1-binding variable database)` give
the code a [KV namespace](#cloudflare-kv-namespace) or a
[D1 database](#cloudflare-d1-database) as `env.variable`.

### What changes

- The Worker is published again whenever its script, a file of its
  assets, a variable, a secret's value or a binding changes; only the
  files Cloudflare does not have yet are uploaded.
- Changing `#:crons` only changes when it runs.
- Changing the domain moves the Worker to the new one, in place. Changing
  its name replaces it.
- Hidden files, whose name starts with a dot, are not served.
- Deleting it deletes its domain and its schedule too.

The Worker belongs to the account of the token. If the token reaches
several accounts, set `CLOUDFLARE_ACCOUNT_ID`, or use
`cloudflare-account-id`:

```scheme
(parameterize ((cloudflare-account-id "0123456789abcdef"))
  (with-stage "prod" ...))
```

## cloudflare-kv-namespace

A key-value store for Workers, given to them with `kv-binding`.

```scheme
(define visits (cloudflare-kv-namespace "visits"))
```

| Argument | Default | |
|---|---|---|
| `#:title` | the resource name and the stage | its title, such as `visits-prod` |

Output: `id`. Changing its title renames it, in place; its keys are kept.

## cloudflare-d1-database

A SQLite database for Workers, given to them with `d1-binding`.

```scheme
(define hits (cloudflare-d1-database "hits" #:schema "schema.sql"))
```

```sql schema.sql
CREATE TABLE IF NOT EXISTS hits (path TEXT, at TEXT);
CREATE INDEX IF NOT EXISTS hits_at ON hits (at);
```

| Argument | Default | |
|---|---|---|
| `#:schema` | none | a file of SQL statements |
| `#:name` | the resource name and the stage | its name, such as `hits-prod` |

Output: `id`.

The schema is run when the database is created, and the whole file is run
again whenever it changes. Its statements must therefore be safe to run
again: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `INSERT OR
IGNORE`. A new table can be added this way at any time.

A statement that cannot run twice, such as `ALTER TABLE ... ADD COLUMN`,
works once, then makes the next change of the file fail:

```output
chaudron: could not update cloudflare-d1-database/hits: duplicate column name: agent: SQLITE_ERROR
```

> [!CAUTION]
> Changing a database's name replaces it: the new one is empty.
