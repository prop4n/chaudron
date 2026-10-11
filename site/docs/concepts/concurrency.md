title: Concurrency
order: 6
description: Converge independent resources at the same time.
---

Resources are converged one after the other, in the order of the program.
Creating a server takes a while; when resources do not depend on each
other, converge them at the same time with `concurrently`:

```scheme
(define-values (key ip data)
  (concurrently
   (hetzner-ssh-key "me" #:public-key-file "~/.ssh/id_ed25519.pub")
   (hetzner-primary-ip "forge" #:location "fsn1")
   (hetzner-volume "data" #:size 10 #:location "fsn1")))
```

Each expression runs in its own thread, and `concurrently` returns their
values in order.

If one fails, the others finish, then the error is raised, and the stage
deletes nothing.

`call-concurrently` does the same with procedures, for a list built at run
time:

```scheme
(apply call-concurrently
       (map (lambda (name)
              (lambda ()
                (hetzner-server name #:type "cx23" #:location "fsn1")))
            '("web-1" "web-2" "web-3")))
```
