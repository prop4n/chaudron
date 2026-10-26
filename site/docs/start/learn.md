title: Learn chaudron in 10 minutes
order: 2
description: The Scheme you need, a first program explained part by part, and a dry run with no cloud account.
---

This page is for you if you know a little Linux and programming, but not
Scheme, Guile or Guix. At the end, you will have run a first chaudron
program, and know how to read the others.

```prereqs
Time: 10 minutes
Accounts: none
Cost: nothing: no resource is created
You get: a first program, run in dry-run mode, and the words to read the rest of the docs
```

## The Scheme you need

chaudron programs are written in Scheme, run by Guile. Six things are
enough to read them:

| You see | It means | In Python |
|---|---|---|
| `(hetzner-server "web")` | call `hetzner-server` with `"web"`: the parentheses make a call, the procedure comes first | `hetzner_server("web")` |
| `#:type "cx23"` | a named argument | `type="cx23"` |
| `(define server ...)` | name a value | `server = ...` |
| `"web"`, `22`, `#t`, `#f` | a string, a number, true, false | `"web"`, `22`, `True`, `False` |
| `'("web" "api")` | a list of values, not a call | `["web", "api"]` |
| `;; text` | a comment | `# text` |

Indentation is only for reading; what counts is the parentheses. Any
editor highlights the matching one.

## A first program

This program declares a server at Hetzner, in dry-run mode: chaudron says
what it would do, and does nothing.

```explain hello.scm
(use-modules (chaudron)
             (chaudron hetzner))

(with-stage "dev" #:dry-run? #t
  (define server
    (hetzner-server "web" #:type "cx23" #:location "fsn1"))

  (format #t "the server will be at ~a~%" (output server 'ipv4)))
@ (use-modules (chaudron)
Loads chaudron, then its Hetzner provider, `(chaudron hetzner)`: like an
`import` in Python. Each cloud has its provider.
@ (with-stage "dev"
Opens a **stage**, an environment called `dev`. Everything declared inside
belongs to it; another stage, `prod`, would be another copy, with its own
servers. See [Stages](/docs/stages/).
@ #:dry-run? #t
**Dry run**: chaudron reads what exists and reports what it would change,
but changes nothing. Remove it to deploy for real.
@ (define server
Names the result `server`, to use it below.
@ (hetzner-server "web"
Declares a **resource**: a server at Hetzner, called `web` in the program.
At Hetzner it is named `web-dev`, after the stage. Each call makes the real
server match what it says, then returns it.
@ #:type "cx23" #:location "fsn1"
What the server should be: its type, the size of the machine, and where it
runs, Falkenstein. Change one later, and the next run changes the server.
@ (output server 'ipv4)
An **output** of the resource: what Hetzner tells about it, here its public
address. In a dry run, the server does not exist yet, so its address is
unknown.
```

## Run it

Get chaudron, and run the program with it. With Guix:

```sh
$ git clone https://github.com/prop4n/chaudron
$ guix shell -m chaudron/lib/manifest.scm -- guile -L chaudron/lib hello.scm
```

On Debian or Ubuntu:

```sh
$ sudo apt install guile-3.0 guile-json guile-gnutls guile-gcrypt
$ git clone https://github.com/prop4n/chaudron
$ guile -L chaudron/lib hello.scm
```

`-L chaudron/lib` tells Guile where chaudron is. Either way:

```output
chaudron: create hetzner-server/web (dry run)
the server will be at #<unknown hetzner-server/web ipv4>
```

No token was needed: there was nothing to read at Hetzner yet, and nothing
was created. Nothing was written either: a dry run does not touch the
[state](/docs/state/), chaudron's memory of what it made.

## Make it a program

A program can do what a configuration file cannot. Two servers are a loop:

```scheme loop.scm
(use-modules (chaudron)
             (chaudron hetzner))

(with-stage "dev" #:dry-run? #t
  (for-each (lambda (name)
              (hetzner-server name #:type "cx23" #:location "fsn1"))
            '("web" "api")))
```

```output
chaudron: create hetzner-server/web (dry run)
chaudron: create hetzner-server/api (dry run)
```

`(lambda (name) ...)` is a procedure without a name, called once per
element of the list by `for-each`: like `for name in ["web", "api"]:`. A
whole website, its server, its DNS record and its system, fits in a
procedure the same way, and two websites are two calls.

## What happens for real

Without `#:dry-run? #t`, with a Hetzner token, the same program:

1. creates the server, and saves what it learned in `.chaudron/dev/`;
2. on the next run, finds it there, reads the real server, and changes
   nothing if it matches;
3. resizes it if you change `#:type`, deletes it if you remove the call.

That is the whole idea: the program says what should exist, and each run
makes it so.

## Where to go next

- **Deploy something real:** [Installation](/docs/installation/) sets up a
  project, then [Your first deployment](/docs/first-deployment/) creates a
  server, changes it and deletes it, for a few cents.
- **The words:** the [Glossary](/docs/glossary/).
- **How a run works:** [Stages](/docs/stages/), [Resources](/docs/resources/)
  and [State](/docs/state/).
- **Complete programs:** the [Recipes](/docs/load-balancer/).
