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

## How it works

- `with-stage` loads the state of the stage from `.chaudron/<stage>/`, runs
  its body, then deletes the resources of the stage that the body no longer
  declares. If the body raises an error, nothing is deleted.
- Each resource call creates, updates in place, replaces or leaves alone the
  resource, and saves its state immediately.
- State is one s-expression file per resource,
  `.chaudron/<stage>/<kind>/<name>.scm`. It is read as data, never evaluated.
  Commit it, or keep it somewhere safe: it is how chaudron finds your
  resources again.
- Resources can be passed to other resources; they stand for their `id`.
  `(output resource 'ipv4)` gives any other output.
- `(destroy-stage "prod")` deletes everything in a stage.

## Hetzner

```scheme
(hetzner-ssh-key "me" #:public-key "ssh-ed25519 AAAA...")
(hetzner-server "forge"
                #:type "cx23"            ;changing it resizes in place
                #:location "fsn1"        ;changing it replaces the server
                #:image "debian-12"      ;idem
                #:ssh-keys (list key))   ;idem
```

The token comes from `HCLOUD_TOKEN`, or from `(with-hetzner token body ...)`.
Outputs: `id`, `ipv4`, `ipv6` for servers; `id`, `fingerprint` for SSH keys.

## Writing a provider

A provider is a module that registers a `make-provider` and wraps
`ensure-resource`:

```scheme
(define thing-provider
  (register-provider!
   (make-provider 'acme-thing
                  #:create (lambda (name props) ... outputs)
                  #:update (lambda (outputs old-props new-props) ... outputs)
                  #:delete (lambda (outputs) ...)
                  #:replace-on '(region))))

(define* (acme-thing name #:key region size)
  (ensure-resource thing-provider name `((region . ,region) (size . ,size))))
```

Props and outputs are alists keyed by symbols. Without `#:update`, any change
replaces the resource.

## Development

```sh
guix shell -m manifest.scm -- guile -L . tests/stage.scm
guix shell -m manifest.scm -- guile -L . tests/hetzner.scm
```

Dependencies: Guile 3, guile-json, guile-gnutls.
