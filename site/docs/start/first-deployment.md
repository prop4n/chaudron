title: Your first deployment
order: 3
description: A server at Hetzner, from nothing to ssh, then gone again.
---

This guide creates a small server at Hetzner Cloud, reachable over SSH,
then deletes it. You need a Hetzner account and an SSH key.

> [!CAUTION]
> Servers cost money while they exist. The one made here costs a few cents
> an hour; the last step deletes it.

## Set up the project

Create a project as shown in [Installation](/docs/installation/#create-a-project),
steps 1 to 3, and open its shell. The commands below run in it.

## Get a token

In the [Hetzner Console](https://console.hetzner.cloud), open a project,
then **Security**, **API tokens**, and generate a token with **Read &
Write** permissions. Put it in a `.env` file next to your script, and keep
that file out of version control:

```sh .env
HCLOUD_TOKEN=your-token
```

## Write the script

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner)
             (ice-9 match))

;; HCLOUD_TOKEN, unless it is already set.
(load-env-file ".env")

(define (deploy dry-run?)
  (with-stage "dev" #:dry-run? dry-run?
    (define key
      (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub"))

    (define ssh
      (hetzner-firewall "ssh" #:rules (list (allow-in 'tcp 22))))

    (define box
      (hetzner-server "box"
                      #:type "cx23"
                      #:location "fsn1"
                      #:ssh-keys (list key)
                      #:firewalls (list ssh)))

    (format #t "ssh root@~a~%" (output box 'ipv4))))

(match (command-line)
  ((_ "dry-run") (deploy #t))
  ((_ "destroy") (destroy-stage "dev"))
  (_ (deploy #f)))
```

Each call declares one resource. The key and the firewall are given to the
server: chaudron knows the server depends on them.

## See what it would do

```sh
$ guile deploy.scm dry-run
```

```output
chaudron: create hetzner-ssh-key/me (dry run)
chaudron: create hetzner-firewall/ssh (dry run)
chaudron: create hetzner-server/box (dry run)
ssh root@#<unknown hetzner-server/box ipv4>
```

Nothing exists yet, so the server's address is unknown.

## Deploy

```sh
$ guile deploy.scm
```

```output
chaudron: create hetzner-ssh-key/me
chaudron: create hetzner-firewall/ssh
chaudron: create hetzner-server/box
ssh root@203.0.113.7
```

The server is called `box-dev` at Hetzner: names are suffixed with the
stage. chaudron saved what it made in `.chaudron/dev/`; run the script
again and it does nothing, since everything matches.

## Change something

Make the server bigger, `#:type "cx33"`, and run it again:

```output
chaudron: update hetzner-server/box (type)
```

The server is resized in place; it is powered off for a moment.

## Clean up

```sh
$ guile deploy.scm destroy
```

```output
chaudron: delete hetzner-server/box
chaudron: delete hetzner-firewall/ssh
chaudron: delete hetzner-ssh-key/me
```

The server is deleted before the key and the firewall it was given.

Next: [Stages](/docs/stages/) explains what a run does, and
[Hetzner Cloud](/docs/hetzner/) lists everything you can declare there.
