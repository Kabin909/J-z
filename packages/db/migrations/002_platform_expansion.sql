-- J&Z Platform expansion migration. Safe to run repeatedly.
create table if not exists node_enrollment_tokens(
  id uuid primary key default gen_random_uuid(),
  node_id uuid not null references nodes(id) on delete cascade,
  token_hash char(64) not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists node_enrollment_tokens_node_idx on node_enrollment_tokens(node_id);

alter table node_credentials add column if not exists secret_encrypted text;
alter table nodes add column if not exists location text;
alter table nodes add column if not exists maintenance_reason text;
alter table nodes add column if not exists last_error text;
alter table servers add column if not exists container_id text;
alter table servers add column if not exists image text;
alter table servers add column if not exists startup_command text;
alter table servers add column if not exists auto_start boolean not null default false;
alter table servers add column if not exists restart_policy jsonb not null default '{"enabled":false,"max_restarts":3,"window_seconds":60,"cooldown_seconds":30}'::jsonb;

create table if not exists server_events(
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references servers(id) on delete cascade,
  type text not null,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists server_events_server_time_idx on server_events(server_id,created_at desc);

create table if not exists server_files_audit(
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references servers(id) on delete cascade,
  user_id uuid references users(id) on delete set null,
  operation text not null,
  path text not null,
  created_at timestamptz not null default now()
);

create table if not exists database_hosts(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  engine text not null check(engine in ('mysql','mariadb','postgresql')),
  host text not null,
  port integer not null,
  username text not null,
  password_encrypted text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists databases(
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references servers(id) on delete cascade,
  host_id uuid not null references database_hosts(id) on delete restrict,
  name text not null,
  username text not null,
  password_encrypted text not null,
  created_at timestamptz not null default now(),
  unique(host_id,name)
);

create table if not exists backup_storage(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  driver text not null check(driver in ('local','s3')),
  config jsonb not null default '{}',
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
alter table backups add column if not exists storage_id uuid references backup_storage(id) on delete set null;
alter table backups add column if not exists checksum text;
alter table backups add column if not exists completed_at timestamptz;
alter table backups add column if not exists error text;

create table if not exists schedule_tasks(
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references schedules(id) on delete cascade,
  action text not null check(action in ('start','stop','restart','kill','backup','command')),
  payload jsonb not null default '{}',
  sequence integer not null default 0,
  continue_on_failure boolean not null default false
);
create index if not exists schedule_tasks_schedule_idx on schedule_tasks(schedule_id,sequence);

create table if not exists plugin_manifests(
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  version text not null,
  manifest jsonb not null,
  enabled boolean not null default false,
  installed_at timestamptz not null default now()
);
create table if not exists plugin_versions(
  id uuid primary key default gen_random_uuid(),
  plugin_id uuid not null references plugin_manifests(id) on delete cascade,
  version text not null,
  compatibility jsonb not null default '{}',
  changelog text,
  artifact_sha256 text,
  created_at timestamptz not null default now(),
  unique(plugin_id,version)
);

create table if not exists panel_versions(
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  channel text not null default 'stable',
  artifact_url text,
  artifact_sha256 text,
  released_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists update_history(
  id uuid primary key default gen_random_uuid(),
  from_version text,
  to_version text not null,
  status text not null,
  backup_id uuid,
  error text,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists login_events(
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete set null,
  identifier text,
  success boolean not null,
  ip inet,
  user_agent text,
  created_at timestamptz not null default now()
);
create index if not exists login_events_user_time_idx on login_events(user_id,created_at desc);

create table if not exists two_factor_secrets(
  user_id uuid primary key references users(id) on delete cascade,
  secret_encrypted text not null,
  enabled boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists recovery_codes(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  code_hash char(64) not null,
  used_at timestamptz,
  unique(user_id,code_hash)
);

create table if not exists feature_flags(
  key text primary key,
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into feature_flags(key,enabled) values
('free_node_claims',false),('plugin_store',false),('automatic_ssl',false),('dns_automation',false),('server_transfer',false),('application_api',true),('webhooks',true)
on conflict(key) do nothing;

create table if not exists system_settings(
  key text primary key,
  value jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create index if not exists activity_logs_time_idx on activity_logs(created_at desc);
create index if not exists notifications_user_read_idx on notifications(user_id,read_at,created_at desc);
create index if not exists nodes_heartbeat_idx on nodes(last_heartbeat);

-- Default role policy: explicit, least-privilege grants for non-super roles.
insert into role_permissions(role_id,permission_id)
select r.id,p.id from roles r join permissions p on p.name in (
  'users.view','nodes.view','servers.view','files.view','files.upload','files.download','files.create','files.update','files.delete',
  'backups.view','backups.create','backups.restore','backups.delete','databases.view','databases.create','databases.delete',
  'domains.view','domains.create','domains.update','domains.delete'
) where r.name='User' on conflict do nothing;
insert into role_permissions(role_id,permission_id)
select r.id,p.id from roles r join permissions p on p.name in (
  'nodes.view','servers.view','servers.update','servers.delete','servers.start','servers.stop','servers.restart','servers.kill','servers.reinstall','servers.transfer',
  'files.view','files.upload','files.download','files.create','files.update','files.delete','backups.view','backups.create','backups.restore','backups.delete',
  'databases.view','databases.create','databases.delete','domains.view','domains.create','domains.update','domains.delete','plugins.view'
) where r.name='Manager' on conflict do nothing;
insert into role_permissions(role_id,permission_id)
select r.id,p.id from roles r join permissions p on p.name in (
  'users.view','nodes.view','servers.view','servers.start','servers.stop','servers.restart','servers.kill','files.view','backups.view','databases.view','domains.view','plugins.view','system.view'
) where r.name='Support' on conflict do nothing;
insert into role_permissions(role_id,permission_id)
select r.id,p.id from roles r join permissions p on p.name in (
  'users.view','users.create','users.update','users.delete','nodes.view','nodes.create','nodes.update','nodes.delete',
  'servers.view','servers.update','servers.delete','servers.start','servers.stop','servers.restart','servers.kill','servers.reinstall','servers.transfer',
  'files.view','files.upload','files.download','files.create','files.update','files.delete','backups.view','backups.create','backups.restore','backups.delete',
  'databases.view','databases.create','databases.delete','domains.view','domains.create','domains.update','domains.delete',
  'plugins.view','plugins.install','plugins.update','plugins.delete','system.view','system.update','system.settings'
) where r.name='Administrator' on conflict do nothing;
