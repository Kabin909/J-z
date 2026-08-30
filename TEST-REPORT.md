# J&Z Panel v3.1 — verification report

## Checks run in the build environment

- `bash -n install.sh installer/install.sh installer/generate-env.sh installer/validate.sh` — PASS
- YAML parse of `docker-compose.yml` — PASS
- `./installer/validate.sh` — PASS (Docker runtime validation skipped because Docker is unavailable in the build environment)
- Search for the previous `//.env` path bug — no matches
- Worker import is constructor-compatible: `import { Redis } from "ioredis"`
- PostgreSQL migration file present and idempotent
- WebSocket `/health` endpoint implemented
- Nginx reverse-proxy configuration is generated only after the application stack is healthy
- HTTPS changes `PANEL_ORIGIN` and recreates API/WS/Web so CORS/origin configuration is not stale

## VPS-side checks performed by the installer

The installer performs OS, architecture, disk, DNS, port, Docker, Compose, source, `.env`, PostgreSQL, Redis, API, Web, WebSocket, Nginx and optional public HTTPS checks.

If a transactional installation fails, it restores the previous `.env` and Nginx configuration and does not delete database volumes or prune Docker images.

## Important limitation

A real Docker build was not executed in this environment because Docker and external package registry access are unavailable here. Therefore this release is **not claimed to be zero-error under every VPS environment**. The installer is designed to fail closed and show the failing service logs instead of reporting a false success.

The current repository also does not contain a real Wings daemon; `wings/` is documentation only. The installer therefore refuses to pretend that option 1/3 is a working Wings deployment.
