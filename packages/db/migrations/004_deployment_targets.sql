-- J&Z deployment targets: VPS, CodeSandbox-compatible dev environments, and Playit tunnels.
create table if not exists deployment_targets(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  kind text not null check(kind in ('VPS','CODESANDBOX','PLAYIT')),
  enabled boolean not null default true,
  config jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists deployment_targets_kind_idx on deployment_targets(kind,enabled);

create table if not exists deployment_ports(
  id uuid primary key default gen_random_uuid(),
  target_id uuid not null references deployment_targets(id) on delete cascade,
  port integer not null check(port between 1 and 65535),
  status text not null default 'FREE' check(status in ('FREE','RESERVED','USED')),
  server_id uuid references servers(id) on delete set null,
  public_address text,
  created_at timestamptz not null default now(),
  unique(target_id,port)
);
create unique index if not exists deployment_ports_server_unique on deployment_ports(server_id) where server_id is not null;

insert into deployment_targets(name,kind,enabled,config) values
('Local VPS','VPS',true,'{"description":"Standard J&Z Wings node / Docker deployment"}'),
('CodeSandbox','CODESANDBOX',true,'{"description":"Development target using an externally exposed sandbox port"}'),
('Playit Tunnel','PLAYIT',false,'{"description":"Playit.gg tunnel integration; administrator must provide agent/tunnel configuration"}')
on conflict(name) do nothing;
