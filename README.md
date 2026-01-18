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

Run `wsl --version` to ensure WSL2 is enabled. Version should be 2.4.4 or higher.

## First Launch
The shell is pre-configured with:
- **zsh** with Oh My Zsh
- **Starship** prompt (shows git branch, kubernetes context, etc.)
- Syntax highlighting and autosuggestions


> [!IMPORTANT]
> After installation, restart Windows Terminal to apply font settings.

## Starting EDA

Once the first-run setup is complete, start EDA with:

```bash
eda-up
```

This will:
1. Clone the [EDA playground](https://github.com/nokia-eda/playground) to `~/nokia-eda/playground`
2. Create a KIND cluster and deploy EDA
3. Load a simulated network topology

First run takes several minutes. Once complete, access EDA at **https://localhost:9443** (admin/admin).


### Resource Requirements

EDA requires **12GB of RAM** and **4+ vCPUs**. Configure memory allocation in **WSL Settings** (search for "WSL Settings" in the Start menu).

## VS Code Integration

To configure VS Code for use with EDA WSL:

```bash
eda-vscode
```

This will:
1. Install the [WSL extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl) if not present
2. Configure the terminal font for proper Nerd Font rendering


To open a directory in VS Code after setup, simply run `code .` from any directory.


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
