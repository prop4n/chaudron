title: Replace a server, keep its address
order: 2
description: A primary IP outlives the server it is given to.
---

Some changes replace a server: a new image, a new location. By default its
replacement gets a new address, and whatever pointed to the old one breaks.
Give the server a primary IP, and the address stays.

> [!NOTE]
> Tested on Hetzner Cloud.

## The program

```scheme deploy.scm
(use-modules (chaudron)
             (chaudron hetzner))

(load-env-file ".env")

(with-stage "demo"
  (define ip
    (hetzner-primary-ip "box" #:location "fsn1"))

  (define box
    (hetzner-server "box"
                    #:type "cx23"
                    #:location "fsn1"
                    #:image "debian-12"
                    #:ipv4 ip))

  (format #t "~a~%" (output box 'ipv4)))
```

```output
chaudron: create hetzner-primary-ip/box
chaudron: create hetzner-server/box
203.0.113.20
```

## Change the image

Move to Debian 13, `#:image "debian-13"`, and run it again:

```output
chaudron: replace hetzner-server/box (image)
203.0.113.20
```

The server was deleted and created again, with a fresh disk, and the same
address. A primary IP belongs to a location: it can only go to servers in
that location.

> [!CAUTION]
> Replacing a server loses the data on its disk. Keep data on a
> [volume](/docs/hetzner/#hetzner-volume): volumes are not replaced with the
> server.
