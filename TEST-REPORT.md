# J&Z Panel v3.2.0 — installer hardening report

## Installer changes

- Existing `.env` secrets are preserved instead of regenerating the PostgreSQL password on every reinstall.
- PostgreSQL `DATABASE_URL` password is URL-encoded when an existing password contains URI-reserved characters.
- Transaction snapshots now record whether the previous Docker stack was present/running and capture existing application image IDs.
- Rollback restores the previous `.env`, Nginx configuration/default site state, UFW changes, and previous application image tags where available.
- A previously running Docker stack is restarted after rollback instead of being left stopped.
- HTTPS uses a webroot ACME challenge and J&Z-owned Nginx configuration instead of allowing Certbot to rewrite the reverse proxy configuration.
- HTTP/HTTPS ordering is explicit: HTTP + ACME validation first, certificate acquisition second, HTTPS Nginx configuration third, production origins fourth, then service recreation and public health checks.
- WebSocket proxying preserves `/ws` instead of stripping the path.
- Docker Compose dependencies use health-aware `service_healthy` conditions for API/WS/Web startup ordering.
- Nginx's default site is backed up and disabled during J&Z installation, then restored on rollback.
- UFW additions are tracked so failed transactions can remove rules they added and disable UFW again if it was previously inactive.
- Installer source validation no longer depends on the old named ioredis import syntax.
- Installer version is now 3.2.0.

## Validation performed in this environment

- Bash syntax checks: PASS for the root installer and installer helper scripts.
- Docker Compose YAML parsing: PASS.
- Docker Compose dependency conditions were structurally checked after the update.
- Full dependency-backed TypeScript compilation was not completed here because `npm install --omit=optional --no-audit --no-fund` exceeded the available execution timeout.
- A real Docker build and end-to-end VPS installation must still be run before claiming universal production-zero-error status.

## Important scope note

The repository still does not contain a real Wings daemon; `wings/` is documentation only. Therefore the installer correctly refuses to claim that option 1/3 can install a functioning Wings daemon from this source.
