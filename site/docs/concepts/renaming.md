title: Renaming resources
order: 5
description: Change a resource's name in the program without replacing it.
---

Renaming a resource in the program looks, to chaudron, like deleting the
old one and declaring a new one: it would create the new resource, then
delete the old. To keep the real resource, say it moved, before declaring
it:

```scheme
(with-stage "prod"
  (moved 'hetzner-server "forge" "forge2")
  (hetzner-server "forge2" #:type "cx23" #:location "fsn1"))
```

```output
chaudron: move hetzner-server/forge to hetzner-server/forge2
chaudron: update hetzner-server/forge2 (name)
```

`moved` takes the kind of the resource, which is the name of the procedure
declaring it, its old name and its new one.

## What it does

- The state of the resource follows, along with the resources that depend
  on it.
- The resource then converges as usual. Its name at Hetzner changes from
  `forge-prod` to `forge2-prod`, in place; pass `#:name "forge-prod"` to
  keep the old one.
- Once the resource is moved, `moved` does nothing: you can leave it in the
  program, or remove it.
- During a [dry run](/docs/dry-runs/), it only says it would move.

## When it refuses

`moved` raises an error, before changing anything, if:

- a resource already has the new name in the state;
- the new name was already declared earlier in the run: call `moved` first.
