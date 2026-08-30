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
