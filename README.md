# 🟧 J&Z Panel v0.6

J&Z Panel is an original, full-stack Minecraft infrastructure control plane with a modern dark/orange UI and a J&Z Wings node architecture.

> This project intentionally does **not** copy Pterodactyl's visual design. It provides a separate J&Z interface around the same class of infrastructure concepts: servers, nodes, console, files, backups, databases, allocations and administration.

## UI

The web application includes:

- Dashboard / telemetry
- Servers
- Live console surface
- Files
- Backups
- Databases
- Network / allocations
- Activity / audit
- Nodes / Wings
- Users
- Eggs
- Domains
- Plugins
- Security
- Settings
- Responsive mobile navigation

See `docs/UI-FEATURES.md` for the complete UI map.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Kabin909/J-ZPanel/main/installer/install.sh -o /tmp/jz-install.sh && sudo bash /tmp/jz-install.sh
```

For a production domain, point `panel.example.com` to the VPS public IP before enabling HTTPS.

## Important

The repository contains J&Z-owned application code and integration code. Upstream third-party components are downloaded by the installer rather than silently copied into this repository. Do not publish secrets, generated credentials, `node_modules`, build output, or production database files.


## One-line VPS bootstrap

The installer can now be downloaded directly to `/tmp`; it bootstraps the complete repository into `/opt/jz-panel` automatically.

```bash
curl -fsSL https://raw.githubusercontent.com/Kabin909/J-ZPanel/main/installer/install.sh -o /tmp/jz-install.sh && sudo bash /tmp/jz-install.sh
```

For a production Panel + Wings deployment, choose `1`, use a real Panel hostname such as `panel.example.com`, then provide the Wings public API address (normally `http://NODE_IP:8080` or an HTTPS reverse-proxy address).
