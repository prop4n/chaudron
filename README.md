<p align="center">
  <img src="site/assets/cauldron@2x.png" width="140" height="140" alt="A pixel-art cauldron, bubbling green">
</p>

<h1 align="center">chaudron</h1>

<p align="center">
  Infrastructure as plain Guile programs.<br>
  <a href="https://chaudron.dev">chaudron.dev</a> ·
  <a href="https://chaudron.dev/docs/">Documentation</a> ·
  <a href="https://chaudron.dev/docs/load-balancer/">Recipes</a>
</p>

chaudron is a Guile library to describe infrastructure as a Scheme program,
and to deploy it by running that program. There is no CLI and no plan to
apply: each resource call converges the real resource right away, then
returns it, with outputs such as its address for the next calls.

```scheme
(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare))

(with-stage "prod"
  (define forge
    (hetzner-server "forge" #:type "cx23" #:location "fsn1"))

  (cloudflare-dns-record "git"
                         #:zone "example.com"
                         #:content (output forge 'ipv4)))
```

```
$ guile deploy.scm
chaudron: create hetzner-server/forge
chaudron: create cloudflare-dns-record/git
```

Run it again and nothing happens. Change the server type and it is resized
in place. Remove a resource from the program and it is deleted. Resize the
server by hand in the Hetzner console, and the next run reports the drift
and undoes it.

## What it manages

| Provider | Resources |
|---|---|
| Hetzner Cloud | servers, SSH keys, firewalls, primary IPs, volumes, networks, load balancers, snapshots |
| Guix System | Guix System installed on Hetzner servers, then deployed with `guix deploy` |
| Cloudflare | DNS records, Workers serving static sites |
| Livebox | port forwards and DHCP leases of an Orange Livebox (experimental) |

Writing a provider takes a few procedures: create, read, update, delete.
See [Writing a provider](https://chaudron.dev/docs/writing-a-provider/).

## Getting started

With Guix, a project says which chaudron it uses in its own `channels.scm`,
next to its program; nothing is installed globally:

```scheme
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

Pin the exact versions once, then run the program with them:

```sh
guix time-machine -C channels.scm -- describe -f channels > channels.lock.scm
guix time-machine -C channels.lock.scm -- shell guile chaudron -- guile deploy.scm
```

On Debian or Ubuntu:

```sh
sudo apt install guile-3.0 guile-json guile-gnutls guile-gcrypt
git clone https://github.com/prop4n/chaudron ~/src/chaudron
GUILE_LOAD_PATH=~/src/chaudron/lib guile deploy.scm
```

Tokens come from the environment, `HCLOUD_TOKEN` or `CLOUDFLARE_API_TOKEN`,
or from a `.env` file read with `load-env-file`. See
[Installation](https://chaudron.dev/docs/installation/) for the details.

[Your first deployment](https://chaudron.dev/docs/first-deployment/) walks
through a server at Hetzner, from nothing to `ssh`.

## How it works

- A stage, like `"prod"`, is one environment. Running its program
  converges each resource in order, then deletes the resources the program
  no longer declares. If the program fails, nothing is deleted.
- What chaudron knows is kept in `.chaudron/`, one small s-expression file
  per resource, read as data and never evaluated. Commit it, or keep it
  somewhere safe.
- `#:dry-run? #t` runs the same program and only reports what would
  change.

The [documentation](https://chaudron.dev/docs/) covers stages, state,
renaming, concurrency, credentials, and every resource.

## Repository

| Directory | |
|---|---|
| `lib/` | the library and its tests |
| `examples/` | programs to start from: a server, a static site, Guix System, a Livebox |
| `site/` | [chaudron.dev](https://chaudron.dev), built with Haunt and deployed with chaudron itself |

## Development

From `lib/`:

```sh
guix shell -m manifest.scm
guile -L . tests/run.scm
```

Each file can also be run alone, such as `guile -L . tests/stage.scm`.

The tests run against fake APIs and fake commands: they need no account and
cost nothing.

## Status

chaudron is young, and its interface may still change.

## License

chaudron is free software, under the GNU General Public License, version 3
or any later version. See [COPYING](COPYING).
