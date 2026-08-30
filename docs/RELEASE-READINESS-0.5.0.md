# J&Z Panel 0.5.0 — Release Readiness

This release closes the major local-runtime blockers found in 0.4.x: Docker Compose no longer requires a pre-created `.env`, Wings can create containers through the authenticated node boundary, server files are rooted under the J&Z node directory, and the WebSocket service validates sessions against PostgreSQL.

## Verification tiers

- **Static verified:** shell syntax, project structure, migration presence, Compose service contract, authentication primitives, Wings container/file handlers.
- **Container verification:** must be run on a machine with Docker Engine/Desktop.
- **Production verification:** must be run on a Linux VPS with Docker, PostgreSQL, Redis, TLS and a real Wings node.

J&Z deliberately does not mark a feature as production-ready merely because its UI exists. A real status must come from the backend/node and failed operations must remain visible.
