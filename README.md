# J&Z Panel 0.7.1

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/Kabin909/J-z/main/installer/install.sh -o /tmp/jz-install.sh && sudo bash /tmp/jz-install.sh
```

The installer can deploy Panel, Wings, or both. It creates `.env` when `.env.example` is missing and builds the services with Docker Compose.

## Build failure: `Could not find a declaration file for module 'pg'`
The API, worker, and WebSocket packages include local `pg` declarations and the API package also includes `@types/pg`, preventing this TypeScript failure.

## Production domain
Point `panel.example.com` to the VPS, select Panel or Panel + Wings, and enter the domain when prompted. The installer configures Nginx and can request a Let's Encrypt certificate.

## Management

```bash
sudo jz-panel
```

Available operations include status/health, repair, update, backup, and uninstall.


## v0.8.0-patch1 installer/build fixes

This release fixes the Docker build issue caused by the `ioredis` TypeScript constructor import in the API/worker workspaces. It also makes the installer safer around `.env` creation, bundled PostgreSQL TLS, DNS/HTTPS ordering, and failed Docker builds.

Before installation:

```bash
cd /opt/jz-panel
bash installer/preflight.sh
sudo bash installer/install.sh
```

For a domain, point its A record to the VPS IPv4 first. The installer verifies DNS before requesting Let's Encrypt. If DNS is not ready, it leaves the panel on HTTP rather than failing the installation.
