## 0.5.0 — Full-stack runtime hardening

- Fixed authenticated Wings container creation path used by worker installation jobs.
- Added safe node filesystem operations rooted under `/var/lib/jz-wings/servers/<id>`.
- Hardened WebSocket session validation against PostgreSQL sessions.
- Added username and password security endpoints.
- Added migration for session/resource/allocation integrity.
- Installer now installs Go when native Wings is selected.

# Changelog

## 0.4.3 — Deployment Fabric

- Added explicit VPS, CodeSandbox and Playit deployment targets.
- Added transactional deployment-port reservation.
- Added admin Deployment workspace.
- Added CodeSandbox development bootstrap and environment template.
- Added provider public-address/template support without fabricating URLs.
- Added deployment-mode documentation and Playit operational guidance.

# Changelog

## 0.4.2 — Server Management & Runtime Hardening

- Removed create-server UI actions from the public/admin interface.
- Kept server lifecycle management focused on existing workloads.
- Added idempotent runtime compatibility migration for server image, startup command and auto-start fields.
- Added Docker host-gateway mapping so a host-installed J&Z Wings node is reachable from the worker container.
- Added same-origin WebSocket reverse proxying through Nginx.
- Improved Compose process/health startup behavior.
- Added explicit workspace manifests for database/shared packages.
- Removed the Wings server-creation endpoint; Wings is now focused on managing existing workloads.
- Bumped J&Z runtime version to 0.4.2.

# Changelog

## 0.4.1 — local startup hardening

- Docker Compose no longer hard-fails when `.env` is absent during local development.
- Added development-only secret fallbacks for direct `docker compose up --build`.
- Added service restart policies and container health checks.
- Windows installer now generates fresh random `.env` secrets.
- macOS installer refreshes local secrets when OpenSSL is available.
- Added `.dockerignore` so `.env` secrets are never copied into build contexts.
- Added a dedicated Windows test guide.
- Kept the J&Z scenic wallpaper/dark glass UI direction and original J&Z branding.

## 0.4.0
- Replaced the UI screenshot wallpaper with the supplied scenic J&Z background.
- Fixed one-line installer bootstrap when executed through `/dev/fd`.
- Added Linux package-manager detection and KVM awareness.
- Added Windows Docker Desktop and WSL2 guidance and macOS Docker installer.
- Hardened default Compose port bindings to localhost.
- Fixed generated `DATABASE_URL` after secret generation.
- Fixed Wings disk total telemetry.


## 0.3.0

- Expanded J&Z API with node, server, admin, activity, notification, eggs, domain, backup, database-host, plugin and feature-flag endpoints.
- Added server creation transactions and Redis lifecycle jobs.
- Added worker-to-Wings Docker lifecycle dispatch.
- Added timestamped HMAC node request protocol.
- Added node heartbeat ingestion and credential encryption at rest.
- Added local-node bootstrap flow for combined Panel + Wings installs.
- Added installer VPS workflow and expanded command/reference documentation.
- Added production threat model and explicit production-gap register.
- Expanded the UI module pages to read real backend records instead of showing only static placeholders.
