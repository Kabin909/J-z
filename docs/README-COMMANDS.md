# J&Z Commands

## Development — Linux/macOS/Windows Docker Desktop

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f api
docker compose logs -f worker
docker compose logs -f ws
docker compose down
```

Open:

```text
http://localhost:5173
```

## Linux installer

```bash
sudo bash installer/install.sh
```

Remote bootstrap:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Kabin909/J-Z-Test/main/installer/install.sh)
```

## Wings

```bash
systemctl status jz-wings --no-pager
journalctl -u jz-wings -f
curl -fsS http://127.0.0.1:8080/health
```

## Windows

```powershell
Set-Location .\jz-panel
.\installer\install.ps1
```

## macOS

```bash
./installer/install.command
```

## WSL2 Wings on Windows

Inside the WSL Linux distribution:

```bash
cd /path/to/jz-panel
sudo bash installer/install.sh
```

Use option `3` for Wings.
