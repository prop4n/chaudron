;; Tests for primary IPs, volumes, networks, load balancers, snapshots and
;; everything servers can be given.

(use-modules (chaudron)
             (chaudron hetzner)
             (chaudron state)
             (ice-9 exceptions)
             (srfi srfi-26)
             (srfi srfi-64)
             (tests fake-hetzner))

(define-syntax-rule (in-stage name body ...)
  (quietly (lambda () (with-stage name body ...))))

(define (fields json . keys)
  (map (cut assoc-ref json <>) keys))

(define* (server-json id #:key (name "web") (type "cx23") (ipv4-id 100)
                      (ipv4 "1.1.1.1") (labels '()))
  `(("id" . ,id)
    ("name" . ,name)
    ("server_type" . (("name" . ,type)))
    ("public_net" . (("ipv4" . (("id" . ,ipv4-id) ("ip" . ,ipv4)))))
    ("labels" . ,labels)))

(test-begin "hetzner-resources")

(parameterize ((state-directory (mkdtemp "/tmp/chaudron-test-XXXXXX")))

  (test-equal "creates an unassigned primary IP"
    '("5.6.7.8" ((POST "/primary_ips")) ("ipv4" "fsn1" "unassigned" #f))
    (with-api (`(201 . (("primary_ip" . (("id" . 11) ("ip" . "5.6.7.8")))
                        ("action" . null))))
      (let ((ip (in-stage "ip" (hetzner-primary-ip "front" #:location "fsn1"))))
        (list (output ip 'ip)
              (routes)
              (fields (body 0) "type" "location" "assignee_type"
                      "auto_delete")))))

  (test-equal "creates a protected volume"
    '(((POST "/volumes") (POST "/volumes/5/actions/change_protection"))
      (10 "fsn1" "ext4")
      #t)
    (with-api (`(201 . (("volume" . (("id" . 5) ("linux_device" . "/dev/sdb")))
                        ("action" . ,(action 1 "success"))
                        ("next_actions" . #())))
               (done 2))
      (in-stage "vol" (hetzner-volume "data" #:size 10 #:location "fsn1"
                                      #:protected? #t))
      (list (routes)
            (fields (body 0) "size" "location" "format")
            (assoc-ref (body 1) "delete"))))

  (define (volume-json size)
    `(("id" . 5) ("name" . "data") ("size" . ,size)
      ("protection" . (("delete" . #t)))))

  (test-equal "grows a volume"
    '((GET "/volumes/5") (POST "/volumes/5/actions/resize"))
    (with-api ((ok "volume" (volume-json 10)) (done 3))
      (in-stage "vol" (hetzner-volume "data" #:size 20 #:location "fsn1"
                                      #:protected? #t))
      (routes)))

  (test-assert "refuses to shrink a volume"
    (guard (e ((error? e) #t))
      (with-api ((ok "volume" (volume-json 20)))
        (in-stage "vol" (hetzner-volume "data" #:size 10 #:location "fsn1"
                                        #:protected? #t)))
      #f))

  (test-equal "creates a network with its subnets"
    '(((POST "/networks")) "10.0.0.0/16" ("cloud" "eu-central" "10.0.1.0/24"))
    (with-api ('(201 . (("network" . (("id" . 9))))))
      (in-stage "net" (hetzner-network "private" #:subnets '("10.0.1.0/24")))
      (list (routes)
            (assoc-ref (body 0) "ip_range")
            (fields (vector-ref (assoc-ref (body 0) "subnets") 0)
                    "type" "network_zone" "ip_range"))))

  (test-equal "adds a subnet"
    '(((GET "/networks/9") (POST "/networks/9/actions/add_subnet"))
      "10.0.2.0/24")
    (with-api ((ok "network" '(("id" . 9) ("name" . "private")
                               ("ip_range" . "10.0.0.0/16")
                               ("subnets" . #((("ip_range" . "10.0.1.0/24"))))))
               (done 1))
      (in-stage "net" (hetzner-network "private"
                                       #:subnets '("10.0.1.0/24" "10.0.2.0/24")))
      (list (routes) (assoc-ref (body 1) "ip_range"))))

  (test-equal "creates a load balancer"
    '("9.9.9.9" (80 8080 "http") 42 #f)
    (with-api (`(201 . (("load_balancer"
                         . (("id" . 4)
                            ("public_net" . (("ipv4" . (("ip" . "9.9.9.9")))))))
                        ("action" . ,(action 1 "success")))))
      (let ((lb (in-stage "lb" (hetzner-load-balancer
                                "front" #:location "fsn1"
                                #:services (list (forward 'http 80 #:to 8080))
                                #:targets '(42))))
            (target (vector-ref (assoc-ref (body 0) "targets") 0)))
        (list (output lb 'ipv4)
              (fields (vector-ref (assoc-ref (body 0) "services") 0)
                      "listen_port" "destination_port" "protocol")
              (assoc-ref (assoc-ref target "server") "id")
              (assoc-ref target "use_private_ip")))))

  (test-equal "updates services and targets"
    '((GET "/load_balancers/4")
      (POST "/load_balancers/4/actions/update_service")
      (POST "/load_balancers/4/actions/add_service")
      (POST "/load_balancers/4/actions/remove_target"))
    (with-api ((ok "load_balancer" '(("id" . 4) ("name" . "front")
                                     ("load_balancer_type" . (("name" . "lb11")))
                                     ("algorithm" . (("type" . "round_robin")))))
               (done 2) (done 3) (done 4))
      (in-stage "lb" (hetzner-load-balancer
                      "front" #:location "fsn1"
                      #:services (list (forward 'http 80 #:to 9090)
                                       (forward 'tcp 22))))
      (routes)))

  (test-equal "takes a snapshot of a server"
    '(77 ((POST "/servers/42/actions/create_image")) "snapshot")
    (with-api (`(201 . (("image" . (("id" . 77)))
                        ("action" . ,(action 1 "success")))))
      (let ((snapshot (in-stage "snap" (hetzner-snapshot "base" #:server 42))))
        (list (output snapshot 'id) (routes) (assoc-ref (body 0) "type")))))

  (test-equal "creates a server with everything"
    '(((POST "/servers")
       (POST "/servers/43/actions/enable_backup")
       (POST "/servers/43/actions/change_protection"))
      (#(5) #t #(9) 11 "web")
      (#t #t))
    (with-api (`(201 . (("server" . ,(server-json 43))
                        ("action" . ,(action 1 "success"))))
               (done 2) (done 3))
      (in-stage "full" (hetzner-server "web" #:type "cx23" #:location "fsn1"
                                       #:volumes '(5) #:networks '(9)
                                       #:ipv4 11 #:backups? #t #:protected? #t
                                       #:labels '(("role" . "web"))))
      (list (routes)
            (list (assoc-ref (body 0) "volumes")
                  (assoc-ref (body 0) "automount")
                  (assoc-ref (body 0) "networks")
                  (assoc-ref (assoc-ref (body 0) "public_net") "ipv4")
                  (assoc-ref (assoc-ref (body 0) "labels") "role"))
            (fields (body 2) "delete" "rebuild"))))

  (test-equal "moves a server to a primary IP"
    '("5.6.7.8"
      ((GET "/servers/44")
       (POST "/servers/44/actions/poweroff")
       (POST "/primary_ips/100/actions/unassign")
       (DELETE "/primary_ips/100")
       (POST "/primary_ips/11/actions/assign")
       (POST "/servers/44/actions/poweron")
       (GET "/servers/44")))
    (begin
      (with-api (`(201 . (("server" . ,(server-json 44 #:name "swap"))
                          ("action" . ,(action 1 "success")))))
        (in-stage "swap" (hetzner-server "swap" #:type "cx23"
                                         #:location "fsn1")))
      (with-api ((ok "server" (server-json 44 #:name "swap"))
                 (done 2) (done 3) '(204 . #f) (done 4) (done 5)
                 (ok "server" (server-json 44 #:name "swap" #:ipv4-id 11
                                           #:ipv4 "5.6.7.8")))
        (let ((server (in-stage "swap" (hetzner-server "swap" #:type "cx23"
                                                       #:location "fsn1"
                                                       #:ipv4 11))))
          (list (output server 'ipv4) (routes))))))

  (test-equal "corrects labels changed behind its back"
    '(((GET "/servers/44") (PUT "/servers/44")) (("chaudron/stage" . "swap")))
    (with-api ((ok "server" (server-json 44 #:name "swap" #:ipv4-id 11
                                         #:ipv4 "5.6.7.8"
                                         #:labels '(("role" . "db"))))
               '(200 . (("server" . ()))))
      (in-stage "swap" (hetzner-server "swap" #:type "cx23" #:location "fsn1"
                                       #:ipv4 11))
      (list (routes) (assoc-ref (body 1) "labels"))))

  (test-equal "upgrades the state of older versions without touching the server"
    '((GET "/servers/42") (PUT "/servers/42"))
    (begin
      (save-entry! "old" '((kind . hetzner-server) (name . "forge") (seq . 1)
                           (props (name . "forge") (type . "cx22")
                                  (location . "fsn1") (image . "debian-12")
                                  (ssh-keys))
                           (outputs (id . 42) (ipv4 . "1.2.3.4"))))
      (with-api ((ok "server" (server-json 42 #:name "forge" #:type "cx22"))
                 '(200 . (("server" . ()))))
        (in-stage "old" (hetzner-server "forge" #:type "cx22"
                                        #:location "fsn1"))
        (routes)))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "hetzner-resources")
(exit (zero? failures))
