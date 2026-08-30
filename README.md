# J&Z Panel — clean VPS foundation

This is a **new project**, independent of the old J&Z ZIP. It contains no VPS IP, SSH username, SSH password, or other private deployment details.

## What this release fixes

- Correct `ioredis` default import for the worker TypeScript build.
- Pinned package versions instead of floating `latest` versions.
- Node 22 + npm 10 compatibility target.
- Docker Compose health checks for PostgreSQL, Redis and API.
- Internal API/WebSocket ports bound to `127.0.0.1` instead of being exposed publicly.
- Robust Debian 12+/Ubuntu 22.04+ checks.
- Docker CE + Buildx + Compose plugin installation when Docker is missing.
- Duplicate Sury PHP source detection/disablement for the common duplicate-source warning.
- Nginx configuration validation before reload.
- Domain validation and VPS-IP fallback.
- Optional Let's Encrypt HTTPS with an explicit email prompt.
- UFW rules that preserve the detected SSH port.
- Persistent installer log at `/var/log/jz-panel-install.log`.
- Secrets generated locally with OpenSSL and never hardcoded.
- Browser favicon only; no forced logo on the web page.

## Important scope

This ZIP is a **foundation release**, not yet a finished Pterodactyl replacement. The production authentication system, user/admin RBAC, server lifecycle API, file manager, plugin/mod manager, node registration protocol, and complete Wings daemon still require implementation and integration tests. The installer therefore does not pretend that a missing Wings implementation is already production-ready.

## Install

```bash
sudo bash install.sh
```

The installer asks for the panel domain. Leave it blank to use the VPS public IPv4 address.

For a public domain, point DNS to the VPS first. HTTPS can then be enabled during installation.
