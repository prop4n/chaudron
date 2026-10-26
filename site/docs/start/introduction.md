title: What is chaudron?
order: 1
description: Infrastructure written as a program: what that means, and where to start.
---

chaudron lets you write your infrastructure as a program: the servers you
rent, their DNS records, and the system that runs on them. You run the
program, and chaudron makes the real infrastructure match it. This is
called infrastructure as code.

You do not need to know Scheme, the language of the programs, nor Guix, to
start: [Learn chaudron in 10 minutes](/docs/learn/) shows the little you
need, and runs a first program without any cloud account.

## By hand, then with chaudron

Putting a website online by hand looks like this:

1. In the Hetzner console, create a server, and copy its address.
2. In the Cloudflare console, create a DNS record, and paste the address.
3. Log in to the server, install nginx, and edit its configuration.
4. Do it all again for a staging copy, a little differently each time.

A few months later, nobody quite knows what is running, nor how to make it
again. With chaudron, the same infrastructure is a file:

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron cloudflare))

(with-stage "prod"
  (define server
    (hetzner-server "web" #:type "cx23" #:location "fsn1"))

  (cloudflare-dns-record "www"
                         #:zone "example.com"
                         #:content (output server 'ipv4)))
```

```output
chaudron: create hetzner-server/web
chaudron: create cloudflare-dns-record/www
```

The address Hetzner gives the server goes to the DNS record as a plain
value: nothing to copy by hand. And the file says what exists:

- run it again, and nothing changes;
- change the server type, and it is resized;
- remove the record from the file, and it is deleted;
- resize the server by hand in the console, and the next run puts it back.

With [Guix System](/docs/guix-system/), even the system of the server,
nginx and its configuration, is part of the program.

## What it manages

| Provider | Resources |
|---|---|
| [Hetzner Cloud](/docs/hetzner/) | servers, SSH keys, firewalls, primary IPs, volumes, Storage Boxes, networks, load balancers, snapshots |
| [Guix System](/docs/guix-system/) | Guix System installed and deployed on Hetzner servers, or [on Oracle Cloud](/docs/oracle/#oracle-guix-system) |
| [Cloudflare](/docs/cloudflare/) | DNS records, Workers, KV namespaces, D1 databases |
| [Oracle Cloud](/docs/oracle/) | buckets, files, images imported from them, networks, instances |
| [Livebox](/docs/livebox/) | port forwards and DHCP leases of an Orange Livebox, experimental |

You can [write your own provider](/docs/writing-a-provider/): it is a
module with a few procedures.

## Choose your path

**New to all this.** [Learn chaudron in 10 minutes](/docs/learn/): the
Scheme you need, a first program explained part by part, and a dry run
with no account. The [Glossary](/docs/glossary/) explains the words.

**Ready to deploy something real.** [Installation](/docs/installation/)
sets up a project, then [Your first deployment](/docs/first-deployment/)
creates a server at Hetzner, changes it, and deletes it, for a few cents.

**Building complete infrastructure.** [Guix System](/docs/guix-system/)
for the machines, [Stages](/docs/stages/) for several environments, the
[Recipes](/docs/load-balancer/) for complete programs, and
[Writing a provider](/docs/writing-a-provider/) for the services chaudron
does not know yet.

> [!NOTE]
> chaudron is young: its interface may still change.
