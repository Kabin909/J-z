# J&Z Platform Support

## Supported panel hosts

### Linux
Production panel installation is supported on Linux distributions with Docker and a supported package manager. The installer detects Debian/Ubuntu (`apt`), RHEL/Fedora (`dnf`/`yum`), Alpine (`apk`) and Arch (`pacman`).

KVM is a virtualization technology, not a Linux distribution. J&Z works inside a KVM virtual machine as long as the guest OS meets the requirements.

### Windows
The J&Z Panel can be tested with Docker Desktop. Real J&Z Wings is a Linux Docker node; on Windows, use WSL2/Linux for Wings rather than exposing Docker Desktop's host socket publicly.

### macOS
The J&Z Panel can be tested with Docker Desktop using `installer/install.command`. Real Wings should run on a Linux VPS/VM.

## Remote architecture

```text
Browser
  -> J&Z Panel/API
  -> authenticated node boundary
  -> J&Z Wings (Linux)
  -> Docker
  -> server container
```

Never expose the Docker daemon TCP socket directly to the internet.
