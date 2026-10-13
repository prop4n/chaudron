title: Livebox
order: 5
description: Port forwards and DHCP leases of an Orange Livebox, on the local network.
---

```scheme
(use-modules (chaudron) (chaudron livebox))
```

> [!CAUTION]
> This provider is experimental. It uses the Livebox's undocumented API,
> was only tried on a Livebox Fibre, and a firmware update may break it.

## Setup

chaudron talks to the Livebox on the local network, as its web interface
does. It reads the credentials from `LIVEBOX_USERNAME`, `admin` by default,
and `LIVEBOX_PASSWORD`. The Livebox is at `192.168.1.1` by default; set
another address with `livebox-host`:

```scheme
(parameterize ((livebox-host "192.168.1.254"))
  (with-stage "home" ...))
```

## Example

```scheme home.scm
(with-stage "home"
  (livebox-port-forward "headscale" #:port 443 #:to "192.168.1.202")
  (livebox-port-forward "stun" #:port 3478 #:to "192.168.1.203"
                        #:protocol 'udp)
  (livebox-dhcp-lease "server" #:mac "aa:bb:cc:00:11:22"
                      #:ip "192.168.1.200"))
```

## livebox-port-forward

Forwards a port of the public address to a device on the local network.

| Argument | Default | |
|---|---|---|
| `#:port` | required | a number, or a range such as `"8000-8100"` |
| `#:to` | required | the address of the device |
| `#:internal-port` | `#:port` | the port on the device |
| `#:protocol` | `'tcp` | `'udp`, or `'both` |
| `#:enabled?` | `#t` | `#f` keeps the rule without applying it |

Output: `id`.

The resource name is the rule's name in the Livebox, made of letters,
digits, `-` and `_`. Declaring the name of an existing rule, as shown in the
web interface, takes it over. Everything else changes in place.

## livebox-dhcp-lease

Always gives the same address to a device.

| Argument | Default | |
|---|---|---|
| `#:mac` | required | the device's MAC address |
| `#:ip` | required | its address |

Output: `mac`. Changing the address or the MAC replaces the lease.
