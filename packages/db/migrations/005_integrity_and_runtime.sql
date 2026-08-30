-- J&Z Panel 0.5.0 integrity/runtime hardening. Safe and idempotent.
alter table sessions add column if not exists last_seen_at timestamptz;
alter table users add column if not exists disabled_at timestamptz;
alter table nodes add column if not exists heartbeat_interval_seconds integer not null default 10;
alter table servers add column if not exists resource_policy jsonb not null default '{}'::jsonb;
create index if not exists sessions_user_expiry_idx on sessions(user_id, expires_at desc);
create index if not exists servers_status_node_idx on servers(node_id,status);
create index if not exists allocations_available_idx on allocations(node_id,server_id,ip,port);
create unique index if not exists allocations_one_primary_per_server on allocations(server_id) where primary_for_server = true and server_id is not null;
