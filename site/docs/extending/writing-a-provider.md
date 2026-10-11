title: Writing a provider
order: 1
description: Teach chaudron a new kind of resource, with a few procedures.
---

A provider tells chaudron how to manage one kind of resource: how to create
it, read it, update it and delete it. Here is a complete one, managing
files on the local disk, which you can run without any account.

```scheme acme/local-file.scm
(define-module (acme local-file)
  #:use-module (chaudron)
  #:use-module (ice-9 textual-ports)
  #:export (local-file))

(define (write-file! props)
  (call-with-output-file (assq-ref props 'path)
    (lambda (port)
      (display (assq-ref props 'content) port))))

(define local-file-provider
  (register-provider!
   (make-provider 'local-file
                  #:create (lambda (name props)
                             (write-file! props)
                             `((path . ,(assq-ref props 'path))))
                  #:read (lambda (outputs)
                           (let ((path (assq-ref outputs 'path)))
                             (and (file-exists? path)
                                  (cons `((content
                                           . ,(call-with-input-file path
                                                get-string-all)))
                                        outputs))))
                  #:update (lambda (outputs old new)
                             (write-file! new)
                             outputs)
                  #:delete (lambda (outputs)
                             (let ((path (assq-ref outputs 'path)))
                               (when (file-exists? path)
                                 (delete-file path))))
                  #:replace-on '(path))))

(define* (local-file name #:key path content)
  "Declare a file at PATH holding CONTENT."
  (ensure-resource local-file-provider name
                   `((path . ,path) (content . ,content))))
```

```scheme files.scm
(use-modules (chaudron) (acme local-file))

(with-stage "dev"
  (local-file "motd" #:path "motd.txt" #:content "Hello\n"))
```

```sh
$ guile -L . files.scm
```

```output
chaudron: create local-file/motd
```

Change the content and run it again: the file is updated. Edit the file by
hand: the next run reports the drift and writes it back. Remove the
declaration: the file is deleted.

## Props and outputs

Both are association lists keyed by symbols.

- **Props** are what the program asks for. The procedure declaring the
  resource builds them and passes them to `ensure-resource`. Resources found
  in them are replaced by their `id`, and recorded as dependencies.
- **Outputs** are what the provider learns, returned by `create`. They are
  saved in the state, given to the other procedures, and read with
  `output`; the `id` output is what the resource stands for when given to
  others.

## The procedures

| Procedure | Called with | Returns |
|---|---|---|
| `#:create` | the resource name, the props | the outputs |
| `#:read` | the outputs | the props it can observe and fresh outputs, as a pair, or `#f` if the resource is gone |
| `#:update` | the outputs, the old props, the new props | the outputs |
| `#:delete` | the outputs | anything |

Only `create` and `delete` are required.

- Without `#:read`, chaudron cannot notice changes made behind its back.
  `read` only needs to return the props it can observe: the others are
  assumed unchanged.
- Without `#:update`, any change replaces the resource.
- `#:replace-on` lists the props that cannot change in place: changing one
  replaces the resource, deleting it then creating it again.
- `delete` should succeed when the resource is already gone.

## register-provider!

`register-provider!` records the provider under its kind. That is how
chaudron deletes a resource that the program no longer declares: it finds
its provider from the kind saved in the state. The module defining the
provider must be loaded for that, so keep using it while resources of its
kind remain.

## Creating in several steps

When creating a resource takes several calls, the resource may exist before
the last one fails. Call `created!` as soon as it exists, with its outputs,
its props, and the props that do not hold yet with the values they have
instead:

```scheme
(define (create-server name props)
  (let* ((outputs (post-server! props)))
    (created! outputs props '((backups? . #f)))
    (enable-backups! outputs)
    outputs))
```

The resource is saved at once. If `enable-backups!` fails, the next run
finds it, sees that `backups?` is `#f`, and finishes with `update`, instead
of creating another one.

## Reporting and errors

`report` prints a line on the error port, prefixed with `chaudron:`, for
what the user should know beyond the create, update and delete lines that
chaudron prints itself. Errors raised by the procedures are reported with
the operation and the resource they concern.
