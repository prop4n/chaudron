title: Stages
order: 1
description: One environment, deployed by running one program.
---

A stage is one environment, like `"prod"` or `"dev"`. Every resource is
declared inside one, with `with-stage`:

```scheme
(with-stage "prod"
  (hetzner-server "forge" #:type "cx23" #:location "fsn1"))
```

## What a run does

1. `with-stage` loads what chaudron knows about the stage, from
   `.chaudron/prod/`: one small file per resource, see [State](/docs/state/).
2. It runs its body. Each resource call converges one resource, in order,
   and saves its state right away, see [Resources](/docs/resources/).
3. When the body returns, the resources of the stage that it did not
   declare this time are deleted, each before the resources it was given.

Deleting a resource is therefore done by removing it from the program. If
the body raises an error, nothing is deleted: a half-run program cannot
take down what it did not reach.

`with-stage` returns the values of its body.

## Several stages

Stages are independent: each has its own state, and deploying one never
touches the others. Run the same code with two stage names to get two
copies of an environment:

```scheme
(define (environment stage)
  (with-stage stage
    (hetzner-server "web" #:type "cx23" #:location "fsn1")))

(environment "staging")
(environment "prod")
```

At Hetzner, names are suffixed with the stage, `web-staging` and
`web-prod`, so that several stages can share one project. SSH keys are the
exception: Hetzner accepts each key once per project, see
[Staging and production](/docs/staging-and-production/). Cloudflare
records are named as given: two stages declaring the same record fight
over it.

## Deleting a whole stage

`destroy-stage` deletes every resource of a stage, each before the
resources it was given:

```scheme
(destroy-stage "staging")
```

Resources protected against deletion, with `#:protected? #t`, stop it with
an error: turn their protection off first.

## When something fails

In a script, a failed operation stops the program with a one-line message
and exit status 1:

```output
chaudron: could not delete hetzner-server/forge: server deletion is protected
```

At the REPL, or with `(exit-on-failure? #f)`, a `&chaudron-error` is raised
instead. It keeps the original error, so that `hetzner-error?` and the like
still recognize it.
