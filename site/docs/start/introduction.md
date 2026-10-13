title: Introduction
order: 1
description: What chaudron is, and how a deployment looks.
---

chaudron is a Guile library to describe infrastructure, servers, DNS
records, a whole Guix System, as a plain Scheme program, and to deploy it by
running that program.

```scheme deploy.scm
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

```output
chaudron: create hetzner-server/forge
chaudron: create cloudflare-dns-record/git
```

## No CLI, no plan to apply

There is no command to learn and no separate plan step. Each resource call,
like `hetzner-server`, looks at the real resource and makes it match what
the program says, right away. Then it returns the resource, whose outputs,
such as its address, can be given to the next calls.

Since a deployment is a program, the whole of Guile is at hand: procedures
to declare several similar servers, loops, modules shared between projects,
conditions on the environment.

## What it manages

| Provider | Resources |
|---|---|
| [Hetzner Cloud](/docs/hetzner/) | servers, SSH keys, firewalls, primary IPs, volumes, networks, load balancers, snapshots |
| [Guix System](/docs/guix-system/) | Guix System installed and deployed on Hetzner servers, or [on Oracle Cloud](/docs/oracle/#oracle-guix-system) |
| [Cloudflare](/docs/cloudflare/) | DNS records, Workers, KV namespaces, D1 databases |
| [Oracle Cloud](/docs/oracle/) | buckets, files, images imported from them, networks, instances |
| [Livebox](/docs/livebox/) | port forwards and DHCP leases of an Orange Livebox, experimental |

You can [write your own provider](/docs/writing-a-provider/): it is a
module with a few procedures.

## Where to go next

- [Installation](/docs/installation/): what chaudron needs, with or without
  Guix.
- [Your first deployment](/docs/first-deployment/): a server at Hetzner, from
  nothing to `ssh`.
- [Stages](/docs/stages/) and [Resources](/docs/resources/): how a run works.

> [!NOTE]
> chaudron is young: its interface may still change.
