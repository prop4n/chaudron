title: Guix System
order: 2
description: Install Guix System on a Hetzner server, then deploy it with guix deploy.
---

```scheme
(use-modules (chaudron) (chaudron hetzner))
```

`hetzner-guix-system` runs Guix System on a [Hetzner server](/docs/hetzner/).
The first run installs it; then it deploys your configuration with
`guix deploy` whenever it changes.

## What you need

On the machine running chaudron:

- `guix`; Guix can be installed on any distribution;
- `ssh` and `ssh-keyscan`;
- a Guix signing key: `guix archive --generate-key`.

## The configuration

A file whose last expression is an `operating-system`. Start from
`make-hetzner-os`, from `(gnu machine hetzner)`, given the server's type: it
sets the bootloader, the file systems and the network for it.

```scheme forge-os.scm
(use-modules (gnu)
             (gnu machine hetzner))
(use-service-modules web)

(define %base
  (make-hetzner-os "cx23"))

(operating-system
  (inherit %base)
  (host-name "forge")
  (services
   (cons* (service nginx-service-type)
          (operating-system-user-services %base))))
```

## Declaring it

```scheme deploy.scm
(with-stage "prod"
  (define key
    (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))

  (define forge
    (hetzner-server "forge" #:type "cx23" #:location "fsn1"
                    #:ssh-keys (list key)))

  (hetzner-guix-system "forge"
                       #:server forge
                       #:os "forge-os.scm"
                       #:ssh-key key))
```

| Argument | Default | |
|---|---|---|
| `#:server` | required | a `hetzner-server` |
| `#:os` | required | the configuration file |
| `#:ssh-key` | required | the `hetzner-ssh-key` of `#:identity` |
| `#:identity` | `"~/.ssh/id_ed25519"` | the private key to reach the server |

`#:os` and `#:identity` are relative to the directory chaudron runs from.

## The first run

> [!DANGER]
> The first run erases the server's disk.

1. It boots the server into Hetzner's rescue system.
2. It erases the disk and installs a minimal Guix System, reachable over
   SSH as root.
3. It reboots into it, then deploys your configuration with `guix deploy`.

If it is interrupted after rebooting, the next run sees that Guix System
already runs, and only deploys.

## Later runs

It deploys again whenever the configuration file, or the Guix you run, as
given by `guix describe`, changes. Only the file's content is compared:
changes to the modules or files it uses are not noticed. To deploy them,
edit the file; a comment is enough. Touching it is not.

```output
chaudron: update hetzner-guix-system/forge (configuration)
chaudron: 203.0.113.7: deploying /home/me/infra/forge-os.scm
```

If the server was just resized, it waits for it to be back before
deploying.

> [!CAUTION]
> Like `guix system reconfigure`, `guix deploy` does not restart services
> that are running: they keep their old configuration until they are
> restarted, with `herd restart`, or the server reboots. See
> [A static site on Guix System](/docs/static-site/#updating-the-site).

On a new server, HTTPS with `certbot-service-type` works from the first
deployment: nginx starts with a temporary certificate, which certbot then
replaces. [examples/guix-system.scm](https://github.com/prop4n/chaudron/tree/main/examples)
does just that.

## Volumes

Volumes are not mounted for you on Guix System: add a `file-system` for
their `linux-device` output.

## Removing it

Removing `hetzner-guix-system` from the program only stops managing the
system: the server is left as it is. Giving it another server replaces it,
installing Guix System there.
