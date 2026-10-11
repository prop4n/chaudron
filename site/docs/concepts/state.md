title: State
order: 3
description: How chaudron remembers what it made, in plain files.
---

chaudron finds your resources again thanks to its state: one file per
resource, in `.chaudron/<stage>/<kind>/<name>.scm`.

```scheme .chaudron/prod/hetzner-volume/data.scm
((kind . hetzner-volume)
 (name . "data")
 (seq . 4)
 (props (name . "data-prod")
        (size . 10)
        (location . "fsn1")
        (format . "ext4")
        (labels)
        (protected? . #f))
 (outputs
  (id . 104729301)
  (linux-device . "/dev/disk/by-id/scsi-0HC_Volume_104729301"))
 (depends-on))
```

- `props` are the arguments the resource was last converged to;
- `outputs` are what the provider returned, starting with its id;
- `depends-on` lists the resources it was given, to delete them in order;
- `seq` is the order of creation.

The files are only ever read as data, with `read`: they are never
evaluated. Each one is written atomically, as soon as its resource changes.

## Keep it

Without its state, chaudron does not know your resources: running the
program would create them all again. Commit `.chaudron/` with your program,
or keep it somewhere safe.

`state-directory` sets another place than `.chaudron`:

```scheme
(parameterize ((state-directory "/var/lib/infra"))
  (with-stage "prod" ...))
```

## Secrets

The state holds the props in clear. Most are harmless, but a server's
`#:user-data` is stored there too: do not put secrets in it. Tokens are not
part of the state, see [Credentials](/docs/credentials/).

## One run at a time

Two runs of the same stage at the same time could both create a resource,
or overwrite each other's state. chaudron does not prevent it: run one at
a time.
