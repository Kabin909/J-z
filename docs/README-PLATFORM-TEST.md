# J&Z Cross-Platform Test Matrix

| Host | Panel | Wings | Recommended method |
|---|---|---|---|
| Ubuntu/Debian | Yes | Yes | Native Linux installer |
| RHEL/Fedora | Yes | Yes | Native Linux installer |
| Alpine | Yes* | Yes* | Docker-compatible setup; validate package/service specifics |
| Arch | Yes* | Yes* | Docker-compatible setup; validate service specifics |
| KVM VM | Yes | Yes | Guest Linux + native installer |
| Windows | Yes | Linux/WSL2 | Docker Desktop + WSL2 |
| macOS | Yes | Linux VM/VPS | Docker Desktop for panel development |

`*` The installer detects the package manager, but production validation should still be performed on the exact distribution/version you deploy.
