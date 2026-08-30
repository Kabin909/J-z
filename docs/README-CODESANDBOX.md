# J&Z Panel — CodeSandbox mode

CodeSandbox mode is a **development/control-plane target**, not a replacement for J&Z Wings. Browsers and CodeSandbox cannot safely control the host Docker daemon.

## What works

- J&Z web UI
- authentication/session flow
- API development
- dashboard/admin UI
- deployment-target management
- WebSocket application development where the sandbox exposes the port
- external PostgreSQL and Redis

## What must remain on a VPS/node

- J&Z Wings
- Docker lifecycle
- real server containers
- host filesystem operations
- privileged networking

## Start

1. Copy `.env.codesandbox.example` to `.env`.
2. Set `DATABASE_URL` and `REDIS_URL` to real services.
3. Replace development secrets.
4. Run `bash installer/sandbox-start.sh` (or the equivalent npm commands in a Node workspace).
5. Expose the web port configured by `JZ_SANDBOX_PORT`.

## Public URL behavior

J&Z stores a provider URL template only when an administrator supplies one. It does **not** invent a CodeSandbox URL because public preview URL formats can change and are controlled by the platform. Set `JZ_SANDBOX_PUBLIC_URL_TEMPLATE` or configure the CodeSandbox deployment target with a template such as `https://provider-host/{port}` when your environment guarantees that mapping.

## Playit.gg

Playit is treated as a separate tunnel provider. Configure a Playit agent/tunnel outside the browser and give J&Z the resulting public address/template. J&Z never asks a normal user for the Playit secret. Provider credentials stay server-side and are used only by administrator-controlled automation.
