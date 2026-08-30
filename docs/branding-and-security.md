# J&Z Branding + Security

J&Z is an original control-plane implementation. It does not bundle or modify Pterodactyl/Wings source, logos, proprietary assets, or exact UI implementation.

## White-label rules
- Product name: J&Z Panel
- Node agent: J&Z Wings
- Browser title: J&Z Panel
- Footer: Panel made with J&Z Developer KabinXD
- User/admin navigation uses J&Z terminology.
- Third-party products remain named only where they are dependencies (PostgreSQL, Redis, Docker, etc.).

## Security promise
No software can honestly guarantee that nobody can crack it. J&Z instead uses defense-in-depth: Argon2id passwords, secure sessions, RBAC, rate limiting, server-side authorization, scoped API keys, audit logs, authenticated node boundaries, secret redaction, validation, and safe update/rollback workflows.
