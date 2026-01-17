# EDA WSL

A WSL distribution designed for easy 'plug and play' usage with [EDA](https://eda.dev).

**Requires Windows 11.**

## Quick Start

**Ensure you are on the latest version of WSL (WSL 2.4.4 or newer). Use `wsl --update`.**

1. Download the `.wsl` file from the [releases page](https://github.com/eda-labs/wsl-eda/releases/latest)
2. Double click the `.wsl` file to install
3. Open 'EDA' from the start menu, or execute `wsl -d EDA`
4. Complete the first-run setup (certificates, fonts, SSH keys)
5. Run `eda-up` to start the EDA environment
6. Access EDA at https://localhost:9443 (admin/admin)

> [!NOTE]
> Default credentials are `eda:eda`

## WSL Installation

This distro uses WSL2, which requires virtualization enabled in your UEFI/BIOS
(listed as 'SVM (AMD-V)' or 'Intel VT-x' depending on your processor).

Open PowerShell and run:

```powershell
wsl --install
```

Restart your PC, and WSL2 should be installed.

### Version Check

Run `wsl --version` to ensure WSL2 is enabled. Version should be 2.4.4.0 or higher.

## First Launch

On first launch, the setup wizard will:

1. Check internet connectivity and offer proxy configuration if needed
2. Offer to install FiraCode Nerd Font for proper terminal display
3. Import SSH keys from your Windows host (or generate new ones)

The shell is pre-configured with:
- **zsh** with Oh My Zsh
- **Starship** prompt (shows git branch, kubernetes context, etc.)
- Syntax highlighting and autosuggestions

To run the setup again: `/etc/oobe.sh`

> [!IMPORTANT]
> After installation, restart Windows Terminal to apply font settings.

## Starting EDA

Once the first-run setup is complete, start EDA with:

```bash
eda-up
```

This will:
1. Clone the [EDA playground](https://github.com/nokia-eda/playground) to `~/playground`
2. Download required tools (kind, kubectl, kpt, etc.)
3. Create a KIND cluster and deploy EDA
4. Load a simulated network topology

First run takes several minutes. Once complete, access EDA at **https://localhost:9443** (admin/admin).

### Options

```bash
eda-up --status     # Check running environment
eda-up --clean      # Fresh start (removes cluster)
eda-up --no-simulate  # Skip loading topology
```

### Resource Requirements

EDA is configured to run on systems with **4+ vCPUs**. CPU requests are set to minimal values (10m) allowing services to burst as needed.

## Docker Desktop

If you have Docker Desktop installed, you **must** disable WSL integration for the EDA distro:

1. Open Docker Desktop settings
2. Go to Resources → WSL integration
3. Ensure 'EDA' has integration **disabled**

![Docker Desktop integration screenshot](./images/docker_desktop_integration.png)

## DevPod

[DevPod](https://devpod.sh/) enables one-click lab experiences using devcontainers.

To use with EDA WSL:

1. Ensure EDA WSL is running in the background
2. Create an **SSH** provider with:
   - Host: `eda@localhost`
   - Port: `2222`

![DevPod settings screenshot](./images/devpod_settings.png)

> [!NOTE]
> You may need to enable 'Use Builtin SSH' in DevPod settings.

## Developers

Build from another WSL distribution:

```bash
./build.sh
```

This creates `eda.wsl` in `C:\temp`. Double-click to install.

### Manual Build

```bash
# Build
docker build . --tag ghcr.io/eda-labs/eda-wsl-debian

# Export
docker run -t --name wsl_export ghcr.io/eda-labs/eda-wsl-debian ls /
docker export wsl_export > /mnt/c/temp/eda.wsl
docker rm wsl_export

# Install
wsl --install --from-file /mnt/c/temp/eda.wsl
```

## Uninstallation

```powershell
wsl --unregister EDA
```
