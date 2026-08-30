# J&Z production gap register

This file is intentionally honest. A serious infrastructure platform should not mark a feature complete merely because a UI button exists.

## Implemented in this build

- J&Z visual system and wallpaper-driven UI.
- Authentication/session foundation.
- Permission middleware and seeded RBAC policies.
- Node CRUD and credential rotation.
- Node bootstrap endpoint for combined installer mode.
- Timestamped HMAC node protocol.
- Node heartbeat ingestion.
- Transactional server creation with allocation locking.
- Redis job dispatch.
- Worker-to-Wings lifecycle dispatch.
- Wings Docker create/start/stop/restart/kill/delete/inspect/logs.
- Server state updates and audit/event records.
- Admin data endpoints for nodes/servers/eggs/domains/backups/database hosts/plugins/activity.
- Installer menu and VPS documentation.

## Still required before a public production claim

### High priority

- Full console streaming from Docker attach through Wings -> WebSocket -> browser.
- Complete file API: upload/download/read/write/move/copy/archive with canonical path and symlink controls.
- Real backup engine with local/S3 drivers, checksums, restore verification and retention.
- Database provisioning drivers for MySQL/MariaDB/PostgreSQL.
- Full Egg installation engine with isolated install jobs and variable validation.
- DNS provider adapters and ACME/SSL automation.
- Full plugin runtime sandbox/permission system.
- Update artifact signing, migrations, backup/restore and rollback automation.
- TOTP enrollment/verification and recovery-code UX.
- Complete application API with scoped API keys and webhook delivery/retry system.
- Full node-to-node transfer orchestration.
- Full free-node claim concurrency controls and anti-abuse implementation.
- Comprehensive E2E and security test suites.

### Production hardening

- External PostgreSQL/Redis topology.
- Secret manager integration.
- TLS/mTLS strategy for node traffic where appropriate.
- Firewall automation and port policy validation.
- Resource telemetry from cgroups/procfs instead of placeholder metrics.
- Rate limits tuned per endpoint and identity.
- Distributed job idempotency and retry state.
- Observability/metrics/tracing and alerting.
- Disaster recovery exercises.
- Independent security review.

## Definition of done

J&Z is production-ready only when each item has working backend behavior, failure handling, authorization, tests, observability, documentation and recovery behavior.
