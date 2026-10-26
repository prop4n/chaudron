title: Glossary
order: 5
description: The words of chaudron, Guile and Guix, in a sentence each.
---

## Infrastructure as code

**Infrastructure as code**: writing the servers, records and systems you want in files, and letting a
tool make the real ones match, instead of clicking in consoles.

**Provider**: the part of chaudron that knows one service, such as Hetzner Cloud or
Cloudflare: how to create, read, update and delete its resources. See
[Writing a provider](/docs/writing-a-provider/).

**Resource**: one thing a provider manages: a server, an SSH key, a DNS record. Each
resource call, like `hetzner-server`, declares one. See
[Resources](/docs/resources/).

**Stage**: an environment, like `"dev"` or `"prod"`, opened with `with-stage`. Each
stage has its own resources and its own state. See [Stages](/docs/stages/).

**Converge**: what each resource call does: look at the real resource, and create,
update or replace it until it matches the program.

**Props**: the arguments of a resource call, such as `#:type "cx23"`: what the
program wants.

**Outputs**: what the provider tells about a resource once it exists, such as its id
or address, read with `output`.

**State**: what chaudron remembers about the resources it made, one small file each
in `.chaudron/`. Without it, chaudron would create everything again. See
[State](/docs/state/).

**Drift**: a difference between a resource and what chaudron last made, such as a
server resized by hand in the console. The next run reports it, then
undoes it.

**Dry run**: a run that reads what exists and reports what it would change, changing
nothing. See [Dry runs](/docs/dry-runs/).

**Replace**: delete a resource and create it again, when what changed cannot change
in place, such as a server's image. Each resource page says which
changes replace it.

## Guile and Scheme

**Scheme**: a small programming language of the Lisp family, where every call is
written in parentheses: `(f a b)`.

**Guile**: the Scheme that runs chaudron programs, the GNU project's.

**Keyword argument**: a named argument, written `#:name value`, such as `#:type "cx23"`.

**Module**: a file of definitions loaded with `use-modules`, such as
`(chaudron hetzner)`.

## Guix

**Guix**: a package manager in which each package is built from a precise recipe,
so that the same inputs give the same result. It also pins the versions
a project uses.

**Guix System**: an operating system configured entirely by one declaration, a Scheme
file: packages, services, users. Deploying the same file gives the same
system. See [Guix System](/docs/guix-system/).

**guix deploy**: the Guix command that installs a system declaration on a remote machine.
chaudron runs it for you.

**Generation**: each system deployed by Guix is kept as a generation, which you can go
back to if the next one goes wrong.

**Channel**: a source of Guix packages, such as Guix itself or chaudron, given in a
project's `channels.scm`.

**Lock**: `channels.lock.scm`: the exact commits of a project's channels, so that
it gets the same versions everywhere. See
[Installation](/docs/installation/).
