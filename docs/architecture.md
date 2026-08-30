# J&Z Panel Architecture

## Trust boundaries
- Web: unprivileged browser UI. No Docker socket, host shell, or node secrets.
- API: authentication, RBAC, validation, transactions, audit events.
- Worker: asynchronous jobs; never receives browser credentials.
- WebSocket: authenticated realtime boundary; commands must be scope-checked before proxying.
- Wings: only component allowed to interact with Docker on a managed node.

## State model
The API persists intent and authoritative metadata. Wings reports node/container state. UI renders server state returned by API; it must never infer `RUNNING` from a click.

## Failure model
Long-running operations are queued and should transition through explicit states. Node heartbeat expiry drives `OFFLINE`/stale-node handling. Update workflows must snapshot/backup before migration and support rollback checkpoints.
