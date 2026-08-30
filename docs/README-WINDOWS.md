# J&Z Panel — Windows Test Guide

## Prerequisite

Run Docker Desktop with the **Linux/WSL2 engine** before running any J&Z command.

Verify:

```powershell
docker version
```

Both `Client` and `Server` sections must be present.

If the Server section is missing, J&Z has not started yet; fix Docker Desktop/WSL2 first.

## First run

From the `jz-panel` directory:

```cmd
docker compose config
docker compose up --build
```

Open:

```text
http://localhost:5173
```

## Clean reset

```cmd
docker compose down -v
docker compose up --build
```

The `-v` command deletes the local development PostgreSQL volume.

## Diagnostics

```cmd
docker version
docker compose version
docker compose ps
docker compose logs --tail=150 api
docker compose logs --tail=150 web
docker compose logs --tail=150 ws
```

## Wings note

J&Z Wings is a Linux Docker-node agent. For a Windows development machine, use WSL2 or a separate Linux VPS/VM for Wings. The local Linux-node installer uses `host.docker.internal` so the containerized J&Z worker can reach a Wings process running on the host.

## No server creation UI

This release intentionally exposes **server lifecycle management**, not a Create Server button. Existing workloads can be inspected and controlled with start/stop/restart/kill actions according to RBAC.
