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

## 🗄️ Database migration system

J&Z Panel v3.2.0 uses explicit, versioned PostgreSQL migrations. The Docker PostgreSQL container no longer mounts the migration directory as an automatic `docker-entrypoint-initdb.d` script directory. The installer starts PostgreSQL/Redis first and then runs `installer/migrate.sh`.

Migration state is stored in `schema_migrations` with the migration version, name, SHA-256 checksum, and application timestamp. Each pending migration runs inside a PostgreSQL transaction. Applied migrations are skipped; a checksum mismatch stops the deployment instead of silently changing an already-applied migration.

Existing J&Z databases that were created by the older installer are adopted at migration `001` as a baseline without executing `001_init.sql` again, then any newer migrations are applied normally.

To inspect migration state:

```bash
cd /opt/jz-panel
./installer/migrate.sh
```

New schema changes must be added as a new numbered file such as `003_feature_name.sql`; never edit an already-applied migration.
