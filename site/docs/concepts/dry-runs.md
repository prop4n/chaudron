title: Dry runs
order: 4
description: Run the same program, change nothing, see what would change.
---

With `#:dry-run? #t`, a stage runs the same code but changes nothing: it
reads the real resources and reports what it would do.

```scheme
(with-stage "prod" #:dry-run? #t
  ...)
```

```output
chaudron: create hetzner-volume/data (dry run)
chaudron: update hetzner-server/forge (volumes) (dry run)
chaudron: delete hetzner-firewall/web (dry run)
```

The state is not touched either.

## Unknown outputs

The outputs of a resource that a dry run would create do not exist yet.
`output` returns an unknown value for them, printed as:

```output
#<unknown hetzner-server/forge ipv4>
```

`unknown?` recognizes it, to skip what needs a real value:

```scheme
(let ((ip (output forge 'ipv4)))
  (unless (unknown? ip)
    (format #t "ssh root@~a~%" ip)))
```

A resource given an unknown output is reported as changing, since its
value cannot be compared yet.

## A dry-run switch

The examples take the mode from the command line:

```scheme
(use-modules (ice-9 match))

(define (deploy dry-run?)
  (with-stage "prod" #:dry-run? dry-run?
    ...))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "prod"))
  (_ (deploy #f)))
```

`destroy-stage` takes `#:dry-run?` too.
