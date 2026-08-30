-- J&Z Panel 0.4.2 runtime compatibility migration.
alter table servers add column if not exists image text not null default 'ubuntu:24.04';
alter table servers add column if not exists startup_command text not null default '/bin/sh -lc "sleep infinity"';
alter table servers add column if not exists auto_start boolean not null default false;
create index if not exists servers_status_idx on servers(status);
create index if not exists nodes_status_idx on nodes(status);
