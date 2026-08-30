# J&Z security threat model

## Trust boundaries

1. Browser -> Application API
2. Application API -> PostgreSQL/Redis
3. Application API/worker -> J&Z Wings
4. J&Z Wings -> Docker
5. Plugin/update artifact -> installation subsystem

## Rules

- Browser never receives Docker credentials.
- Browser never executes host commands.
- API validates ownership and permissions.
- Node requests are authenticated and time-bounded.
- Secrets are hashed when only verification is required and encrypted when the panel must later use the secret.
- Uploads are validated before processing.
- Paths are canonicalized and checked against the server root.
- Update operations require backup/preflight checks.
- Audit logs redact secrets.

## Important limitation

No software can honestly promise that it can never be cracked. J&Z should instead use defense in depth, least privilege, secure defaults, patching, monitoring, backups, and an external security review before public launch.


## Secret handling

The WebSocket service no longer contains a development cookie-secret fallback. Required secrets must be supplied through the environment. The Compose installer generates random values for local deployments.
