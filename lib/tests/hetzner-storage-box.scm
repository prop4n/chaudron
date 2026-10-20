;; Tests for Storage Boxes, which are in the Hetzner API rather than the
;; Hetzner Cloud API.

(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron hetzner api)
             (chaudron state)
             (ice-9 textual-ports)
             (srfi srfi-26)
             (srfi srfi-64)
             (tests fake-api))

(define-syntax-rule (in-stage name body ...)
  (quietly (lambda () (with-stage name body ...))))

(define (fields json . keys)
  (map (cut assoc-ref json <>) keys))

(define* (box-json status #:key (type "bx11") (ssh? #t) (protected? #t))
  `(("id" . 7)
    ("name" . "data-prod")
    ("status" . ,status)
    ("username" . ,(if (string=? status "active") "u123" 'null))
    ("server" . ,(if (string=? status "active")
                     "u123.your-storagebox.de"
                     'null))
    ("storage_box_type" . (("name" . ,type)))
    ("access_settings" . (("ssh_enabled" . ,ssh?)
                          ("samba_enabled" . #f)
                          ("webdav_enabled" . #f)
                          ("zfs_enabled" . #f)
                          ("reachable_externally" . #f)))
    ("protection" . (("delete" . ,protected?)))
    ("labels" . (("chaudron/stage" . "prod")))))

(define* (data #:key (password "Secret-123456") (type "bx11") (ssh? #t)
               (protected? #t))
  (in-stage "prod"
    (hetzner-storage-box "data" #:type type #:location "fsn1"
                         #:password password
                         #:ssh-keys '("ssh-ed25519 AAAAKEY vm")
                         #:ssh? ssh? #:protected? protected?)))

(test-begin "hetzner-storage-box")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates a Storage Box, and waits for it to be ready"
    '(((POST "/storage_boxes")
       (GET "/storage_boxes/actions/1")
       (GET "/storage_boxes/7") (GET "/storage_boxes/7")
       (POST "/storage_boxes/7/actions/change_protection"))
      ("data-prod" "bx11" "fsn1" "Secret-123456" #("ssh-ed25519 AAAAKEY vm"))
      (#t #f #f #f #f)
      ("u123" "u123.your-storagebox.de"))
    (with-api (`(201 . (("storage_box" . ,(box-json "initializing"))
                        ("action" . ,(action 1 "running"))))
               (ok "action" (action 1 "success"))
               (ok "storage_box" (box-json "initializing"))
               (ok "storage_box" (box-json "active"))
               (done 2))
      (let ((box (data)))
        (list (routes)
              (fields (body 0) "name" "storage_box_type" "location" "password"
                      "ssh_keys")
              (fields (assoc-ref (body 0) "access_settings")
                      "ssh_enabled" "samba_enabled" "webdav_enabled"
                      "zfs_enabled" "reachable_externally")
              (list (output box 'username) (output box 'server))))))

  (test-assert "keeps the password out of the state"
    (let ((state (call-with-input-file
                     (string-append (state-directory)
                                    "/prod/hetzner-storage-box/data.scm")
                   get-string-all)))
      (and (string-contains state "password-digest")
           (not (string-contains state "Secret-123456")))))

  (test-equal "does nothing when nothing changed"
    '((GET "/storage_boxes/7"))
    (with-api ((ok "storage_box" (box-json "active")))
      (data)
      (routes)))

  (test-equal "resets the password when it changes"
    '(((GET "/storage_boxes/7")
       (POST "/storage_boxes/7/actions/reset_password"))
      "Other-123456")
    (with-api ((ok "storage_box" (box-json "active")) (done 3))
      (data #:password "Other-123456")
      (list (routes) (assoc-ref (body 1) "password"))))

  (test-equal "changes its type and access in place"
    '(((GET "/storage_boxes/7")
       (POST "/storage_boxes/7/actions/change_type")
       (POST "/storage_boxes/7/actions/update_access_settings"))
      "bx21" #f)
    (with-api ((ok "storage_box" (box-json "active")) (done 4) (done 5))
      (data #:password "Other-123456" #:type "bx21" #:ssh? #f)
      (list (routes)
            (assoc-ref (body 1) "storage_box_type")
            (assoc-ref (body 2) "ssh_enabled"))))

  (test-equal "undoes access settings changed by hand"
    '((GET "/storage_boxes/7")
      (POST "/storage_boxes/7/actions/update_access_settings"))
    (with-api ((ok "storage_box" (box-json "active" #:type "bx21"))
               (done 6))
      (data #:password "Other-123456" #:type "bx21" #:ssh? #f)
      (routes)))

  (test-equal "asks the Hetzner API, not the Hetzner Cloud API"
    '("https://api.hetzner.com/v1/storage_boxes/7")
    (with-api ((ok "storage_box" (box-json "active" #:type "bx21" #:ssh? #f)))
      (let* ((urls '())
             (transport (hetzner-transport)))
        (parameterize ((hetzner-transport
                        (lambda (method url headers body)
                          (set! urls (cons url urls))
                          (transport method url headers body))))
          (data #:password "Other-123456" #:type "bx21" #:ssh? #f))
        urls)))

  (test-equal "deletes it once it is no longer protected"
    '((GET "/storage_boxes/7")
      (POST "/storage_boxes/7/actions/change_protection")
      (DELETE "/storage_boxes/7"))
    (with-api ((ok "storage_box" (box-json "active" #:type "bx21" #:ssh? #f))
               (done 7)
               `(201 . (("action" . ,(action 8 "success")))))
      (data #:password "Other-123456" #:type "bx21" #:ssh? #f
            #:protected? #f)
      (quietly (lambda () (destroy-stage "prod")))
      (routes))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "hetzner-storage-box")
(exit (zero? failures))
