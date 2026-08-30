# J&Z Panel — Hardened rebuild

A hardened Node/React control-panel foundation with PostgreSQL, Redis, API, worker, WebSocket service, Nginx reverse proxy, HTTPS installer and a local J&Z Wings node agent.

## Included
- Panel + Wings installer menu with domain/IP prompt
- Automatic `.env` generation and secret creation
- PostgreSQL + Redis health/readiness checks
- Persistent user registration/login using JWT
- Admin bootstrap from installer credentials
- Server create/list/delete API and dashboard UI
- Responsive dark/orange UI, favicon, animations and mobile layout
- Docker Compose deployment
- Nginx + optional Let's Encrypt
- UFW setup that preserves the detected SSH port
- Repair, update, health, backup and uninstall actions
- Fixed ioredis TypeScript constructor compatibility problem
- Local Go Wings node agent with systemd and `/health`

## Important scope note
The included `jz-wings` is a J&Z node agent, not a drop-in implementation of the Pterodactyl Wings protocol. Full Pterodactyl-compatible node orchestration requires the Panel-side Wings API/protocol and server lifecycle implementation. This rebuild deliberately does not pretend those interfaces exist.

## Validation performed
- `bash -n installer/install.sh` — passed
- Go build of `wings` — passed
- JSON syntax checks — passed
- Docker Compose YAML parse — passed
- Full npm/Vite/TypeScript build could not be executed in this environment because package installation timed out while fetching dependencies. The previous worker error was addressed by using a runtime-safe CommonJS loading path for ioredis.
