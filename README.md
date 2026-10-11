# chaudron

Infrastructure as plain Guile programs, in the spirit of [alchemy](https://alchemy.run).

No CLI, no plan/apply: a deployment is a Guile script. Each resource call
converges the real infrastructure right away and returns its outputs.

```scheme
(use-modules (chaudron)
             (chaudron hetzner))

(with-stage "prod"
  (hetzner-server "forge" #:type "cx23" #:location "fsn1"))
```

```sh
HCLOUD_TOKEN=... guile -L . deploy.scm
```

Tokens can also live in a `.env` file, read with `(load-env-file ".env")`
at the top of the script: one `NAME=VALUE` per line, variables already set
in the environment taking precedence. Keep it out of version control.

## How it works

- `with-stage` loads the state of the stage from `.chaudron/<stage>/`, runs
  its body, then deletes the resources of the stage that the body no longer
  declares. If the body raises an error, nothing is deleted.
- Each resource call first checks the real resource, when its provider
  supports it. If it was deleted behind chaudron's back, it is created again;
  if it was changed, chaudron reports the drift and brings it back to what
  the code says. Then it creates, updates in place, replaces or leaves alone
  the resource, and saves its state immediately.
- Every change is reported on the error port, e.g.
  `chaudron: update hetzner-server/forge`.
- State is one s-expression file per resource,
  `.chaudron/<stage>/<kind>/<name>.scm`. It is read as data, never evaluated.
  Commit it, or keep it somewhere safe: it is how chaudron finds your
  resources again.
- Resources can be passed to other resources; they stand for their `id`.
  `(output resource 'ipv4)` gives any other output.
- `(destroy-stage "prod")` deletes everything in a stage, each resource
  before the ones it was given.
- When an operation fails, a script stops with a one-line message and exit
  status 1, e.g. `chaudron: could not delete hetzner-server/forge: server
  deletion is protected`. At the REPL, or with `(exit-on-failure? #f)`, a
  `&chaudron-error` is raised instead; it keeps the original error, so that
  `hetzner-error?` and the like still recognize it.

### Dry runs

`(with-stage "prod" #:dry-run? #t ...)` runs the same code but changes
nothing: it reads the real resources and reports what it would do.

```
chaudron: create hetzner-volume/data (dry run)
chaudron: update hetzner-server/forge (volumes) (dry run)
chaudron: delete hetzner-firewall/web (dry run)
```

Outputs of resources that do not exist yet are unknown, printed as
`#<unknown hetzner-server/forge ipv4>`. `destroy-stage` takes `#:dry-run?`
too.

### Concurrency

Resources are converged in order. To converge independent ones at the same
time, wrap them in `concurrently`, which returns their values in order:

```scheme
(define-values (key ip data)
  (concurrently
   (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub")
   (hetzner-primary-ip "forge" #:location "fsn1")
   (hetzner-volume "data" #:size 10 #:location "fsn1")))
```

Each expression runs in its own thread. If one fails, the others finish,
then the error is raised, and the stage deletes nothing.

## Hetzner

The token comes from `HCLOUD_TOKEN`, or from `(with-hetzner token body ...)`.

```scheme
(with-stage "prod"
  (define key
    (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))

  (define web
    (hetzner-firewall "web"
                      #:rules (list (allow-in 'tcp 22)
                                    (allow-in 'tcp 443)
                                    (allow-in 'tcp "8000-8100"
                                              #:from '("10.0.0.0/8"))
                                    (allow-in 'icmp))))

  (define ip   (hetzner-primary-ip "forge" #:location "fsn1"))
  (define data (hetzner-volume "data" #:size 20 #:location "fsn1"))
  (define lan  (hetzner-network "lan" #:ip-range "10.0.0.0/16"))

  (define forge
    (hetzner-server "forge"
                    #:type "cx23"
                    #:location "fsn1"
                    #:image "debian-12"
                    #:ssh-keys (list key)
                    #:firewalls (list web)
                    #:ipv4 ip              ;keeps its address when replaced
                    #:volumes (list data)  ;mounted under /mnt
                    #:networks (list lan)
                    #:user-data "#cloud-config\npackages: [htop]\n"
                    #:backups? #t
                    #:labels '(("role" . "forge"))
                    #:protected? #t))

  (hetzner-load-balancer "front"
                         #:location "fsn1"
                         #:services (list (forward 'http 80 #:to 8080))
                         #:targets (list forge)
                         #:network lan)

  (hetzner-snapshot "forge-base" #:server forge))
```

| Resource | Outputs | Changes that replace it |
|---|---|---|
| `hetzner-ssh-key` | `id`, `fingerprint` | public key |
| `hetzner-firewall` | `id` | — |
| `hetzner-server` | `id`, `ipv4`, `ipv6`, `private-ipv4` | location, image |
| `hetzner-primary-ip` | `id`, `ip` | type, location |
| `hetzner-volume` | `id`, `linux-device` | location, format |
| `hetzner-network` | `id` | zone |
| `hetzner-load-balancer` | `id`, `ipv4`, `ipv6` | location, network |
| `hetzner-snapshot` | `id` | server |

Everything else changes in place. A few things to know:

- Replacing a server loses the data on its disk, but not its volumes, and
  not its address if it has a primary IP.
- Changing a server's type or primary IPs powers it off for a moment.
- A server's `ssh-keys` and `user-data` are only used when it is created.
- Volumes and network ranges can only grow.
- `#:protected? #t` makes Hetzner refuse to delete (or rebuild) the
  resource, including through chaudron: turn it off first.
- Names at Hetzner are suffixed with the stage, `forge-prod` for `forge`,
  so that stages can share a project; `#:name` sets another one.
- `#:labels` are your own; chaudron adds `chaudron/stage` to every resource.
- Firewalls only filter incoming traffic. Their rules are not checked for
  drift.
- `user-data` is stored in the state file: do not put secrets in it.

### Guix System

`hetzner-guix-system` runs Guix System on a server, configured by a file
whose last expression is an `operating-system`, typically based on
`make-hetzner-os` from `(gnu machine hetzner)`, given the server's type:

```scheme
(operating-system
  (inherit (make-hetzner-os "cx33"))
  (host-name "forge")
  ...)
```

Then:

```scheme
(hetzner-guix-system "forge"
                     #:server forge
                     #:os "forge-os.scm"
                     #:ssh-key key)            ;the hetzner-ssh-key of...
                                               ;#:identity, ~/.ssh/id_ed25519
```

The first time, it boots the server into Hetzner's rescue system, **erases
its disk**, installs a minimal Guix System, then deploys the configuration
with `guix deploy`. Afterwards, it deploys again whenever the configuration
file or the Guix in use (`guix describe`) changes. Changes to modules the
file uses are not noticed: touch the file to deploy them.

`#:os` and `#:identity` are relative to the directory chaudron runs from,
and kept as written in the state, so that the state works on any machine.

It needs `guix`, `ssh` and `ssh-keyscan` on the machine running chaudron,
and a Guix signing key (`guix archive --generate-key`). Volumes are not
mounted for you: add a `file-system` for their `linux-device`.

## Cloudflare

The token comes from `CLOUDFLARE_API_TOKEN`, or from
`(with-cloudflare token body ...)`. It needs the "DNS: Edit" permission on
the zones it manages.

```scheme
(use-modules (chaudron) (chaudron hetzner) (chaudron cloudflare))

(with-stage "prod"
  (define forge (hetzner-server "forge" ...))

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

`#:name` defaults to the resource name and is relative to the zone; `"@"`
is the zone itself. Records are named as given, without the stage: two
stages declaring the same record fight over it. Changing a record's zone or
type replaces it; anything else changes in place. Records chaudron manages
carry the comment `chaudron: stage <stage>`.

| Resource | Outputs | Changes that replace it |
|---|---|---|
| `cloudflare-dns-record` | `id`, `zone-id`, `name` | zone, type |

## Livebox (experimental)

Orange's Livebox has an undocumented API on the local network; this was only
tried on a Livebox Fibre, and a firmware update may break it. Credentials
come from `LIVEBOX_USERNAME` (default `admin`) and `LIVEBOX_PASSWORD`; the
address from `livebox-host`, `192.168.1.1` by default.

```scheme
(use-modules (chaudron) (chaudron livebox))

(with-stage "home"
  (livebox-port-forward "headscale" #:port 443 #:to "192.168.1.202")
  (livebox-port-forward "stun" #:port 3478 #:to "192.168.1.203"
                        #:protocol 'udp)
  (livebox-dhcp-lease "server" #:mac "aa:bb:cc:00:11:22"
                      #:ip "192.168.1.200"))
```

A port forward's name is its id in the Livebox: declaring the name of an
existing rule, as shown in its web interface, takes it over. `#:protocol` is
`'tcp`, `'udp` or `'both`; `#:enabled? #f` keeps a rule without applying it.
A lease is replaced when its address or MAC changes.

| Resource | Outputs | Changes that replace it |
|---|---|---|
| `livebox-port-forward` | `id` | — |
| `livebox-dhcp-lease` | `mac` | any |

## Writing a provider

A provider is a module that registers a `make-provider` and wraps
`ensure-resource`:

```scheme
(define thing-provider
  (register-provider!
   (make-provider 'acme-thing
                  #:create (lambda (name props) ... outputs)
                  #:read (lambda (outputs) ... (cons observed-props outputs))
                  #:update (lambda (outputs old-props new-props) ... outputs)
                  #:delete (lambda (outputs) ...)
                  #:replace-on '(region))))

(define* (acme-thing name #:key region size)
  (ensure-resource thing-provider name `((region . ,region) (size . ,size))))
```

Props and outputs are alists keyed by symbols. Without `#:update`, any change
replaces the resource. `#:read` is optional: it returns the props it can
observe on the real resource along with fresh outputs, or `#f` if the
resource no longer exists.

When creating takes several steps, call `(created! outputs props pending)`
as soon as the resource exists, `pending` being an alist of the props that
do not hold yet and the values they have instead, e.g.
`'((protected? . #f))`. The resource is saved at once: if a later step
fails, the next run finds it and finishes the job with `#:update`, instead
of losing track of it.

## Development

The library lives in `lib/`. Everything below runs from there:

```sh
cd lib
guile -L . tests/stage.scm
guile -L . tests/hetzner.scm
guile -L . tests/hetzner-resources.scm
guile -L . tests/hetzner-guix.scm
guile -L . tests/cloudflare.scm
guile -L . tests/env.scm
guile -L . tests/livebox.scm
```

Dependencies: Guile 3, guile-json, guile-gnutls (`guix shell -m manifest.scm`).
