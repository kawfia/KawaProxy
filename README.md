# KawaProxy

Multi-hop privacy proxy infrastructure that chains Ubuntu nodes to hide request origin from network observers at every segment of the path.

## What it does

- Proxies **MTProto** (Telegram) traffic through the node chain
- Proxies **HTTP CONNECT** (forward proxy) through the same chain
- Proxies **REST HTTP** through the same chain
- Operates on a single port `:443` — traffic is indistinguishable from regular TLS 1.3
- Node replacement via DNS change — transparent to clients, no reconfiguration needed

## Node roles

| Variable | Value | Role |
|---|---|---|
| `NEXT_HOP=""` | empty | **node0** — exit node: delivers to Telegram DCs or backend |
| `NEXT_HOP="host:port"` | address | **nodeN** — chain node: forwards to next node |

All nodes run identical software. The only difference is configuration.

## Traffic flow

```
:443  [telemt, ee mode / TLS-fronting]
    │
    ├─ valid MTProto packet
    │       └─→  SOCKS5 :8083  (caddy-l4, internal)
    │                 └─→  nodeN+1:443  (next telemt)
    │                       or Telegram DC directly  (node0 only)
    │
    └─ everything else (non-MTProto TLS)
            └─→  TCP-splice  →  :8443  [Caddy, TLS termination]
                                    │
                                    ├─ HTTP CONNECT  →  caddy FP (forward proxy)
                                    │
                                    └─ GET / POST    →  caddy RP (reverse proxy)
                                                        ├─ NEXT_HOP:443  (nodeN)
                                                        └─ :8081 backend (node0)
```

## Clients

| Client | Connection type |
|---|---|
| Telegram client | MTProto via `:443` |
| HTTP CONNECT proxy client | HTTPS forward proxy via `:443` |
| REST client (backend / MS SQL CLR) | HTTPS REST via `:443` |

## Port map

| Port | Service | All nodes | node0 only | Public |
|---|---|---|---|---|
| `:80` | Caddy — ACME / LE cert | ✅ | | ✅ |
| `:443` | telemt — MTProto + TLS mask | ✅ | | ✅ |
| `:8081` | Backend app (.NET 10) | | ✅ | ❌ |
| `:8082` | Telegram Local Server | | ✅ | ❌ |
| `:8083` | caddy-l4 SOCKS5 (telemt upstream) | ✅ | | ❌ |
| `:8443` | Caddy HTTPS (FP + RP) | ✅ | | ❌ |
| `:9091` | telemt API | ✅ | | ❌ |

## Components

| Component | Role |
|---|---|
| [telemt](https://github.com/telemt/telemt) | MTProto proxy + TLS fronting (`ee` mode) |
| [Caddy](https://caddyserver.com) + [forwardproxy](https://github.com/caddyserver/forwardproxy) | HTTPS termination + HTTP CONNECT forward proxy (caddy FP) |
| [Caddy](https://caddyserver.com) + [caddy-l4](https://github.com/mholt/caddy-l4) | Internal SOCKS5 for MTProto chain routing |
| [Telegram Local Server](https://github.com/tdlib/telegram-bot-api) | Bot API server — node0 only |
| [.NET 10](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu) backend | Application backend — node0 only |
| [LE](https://letsencrypt.org) via Caddy | Automatic TLS certificates |

## Repository structure

```
KawaProxy/
├── .claude/
│   ├── ARCHITECTURE.md     # detailed architecture + config templates
│   └── REFERENCE.md        # variables, versions, links, status
│
├── services/
│   ├── telemt/
│   │   └── telemt.toml.tmpl
│   ├── telegram-bot-api/
│   │   └── telegram-bot-api.service.tmpl
│   └── caddy/
│       ├── Caddyfile.tmpl
│       └── build.sh
│
├── apps/
│   └── backend/
│       ├── src/
│       ├── backend.csproj
│       └── Dockerfile
│
├── deploy/
│   ├── catharsis.sh        # main deploy script
│   └── env/
│       ├── node0.env
│       └── nodeN.env
│
└── README.md
```

## Deploy

```sh
# 1. Copy and edit the env file for the target node
cp deploy/env/node0.env deploy/env/my-node.env
nano deploy/env/my-node.env

# 2. Source the env and run the deploy script
source deploy/env/my-node.env
sudo bash deploy/catharsis.sh
```

See `.claude/REFERENCE.md` for all configuration variables.
