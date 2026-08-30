# J&Z Panel v3.1.1 — verification report

## Source fixes in this release

- Fixed the API login TypeScript syntax error in `apps/api/src/index.ts` (`user.!verifyPassword` -> `!verifyPassword(...)`).
- Added input normalization/validation for registration and safer login error handling.
- Kept the constructor-compatible `import { Redis } from "ioredis"` worker implementation.
- Installer now preserves existing generated database/secret values on repair/reinstall instead of silently rotating the PostgreSQL password against an existing volume.
- Repair/update now loads the existing `.env` configuration before final health checks.
- Installer no longer stores the administrator password in `.env` after bootstrap.
- Build uses `--progress=plain` to avoid the Compose deprecation warning shown by Docker.

## Static checks

- `bash -n install.sh installer/install.sh installer/generate-env.sh installer/validate.sh` — PASS.
- Previous `//.env` path bug — no match.
- Previous worker ioredis constructor/import issue — fixed in source.

## Runtime verification limitation

This build environment does not have Docker available and package installation could not complete within the execution window, so a full Docker build was **not** executed here. The VPS installer itself performs the authoritative Docker build, service readiness, PostgreSQL, Redis, API, WebSocket, Nginx, DNS, ports and optional HTTPS checks and rolls back configuration on failure.

The repository still does not contain the actual Pterodactyl Wings daemon; `wings/` is documentation only. Options that claim a real Wings installation are therefore intentionally refused instead of falsely reporting success.
