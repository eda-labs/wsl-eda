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

## Corporate Proxy

If the first-run setup detects no internet connectivity, it will prompt you to configure proxy settings. This uses `proxyman` to configure proxies for the shell, apt, wget, and Docker.

### Re-select Proxy Region

To change your proxy region or find the fastest proxy for your location:

```bash
/etc/oobe.sh --proxy
```

This will:
1. Prompt you to select your region (EU, NAM, APJ, India, LAT, MEA, China)
2. Ping all available proxies in that region in parallel
3. Automatically select and configure the fastest responding proxy

### Manual Proxy Management

```bash
sudo proxyman set      # Configure proxy
sudo proxyman unset    # Remove proxy
sudo proxyman list     # View current settings
```

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

### Running as DIND (Docker-in-Docker)

For Linux environments or CI pipelines, you can run the image as a true DIND container with its own Docker daemon:

```bash
docker build --network=host -t eda-wsl .

docker run -it --privileged --network=host --name eda-dind eda-wsl
```

The container automatically:
1. Starts the Docker daemon
2. Runs the first-time setup (downloads tools, configures shell)
3. Drops you into zsh with completions enabled

> **Note:** The `--network=host` flag is required if your corporate proxy performs SSL inspection based on source IP ranges (common with Zscaler/Fortinet proxies that treat Docker bridge network differently).

#### Alternative: Using Host Docker Socket

If you prefer to use the host's Docker daemon instead of running a separate one:

```bash
docker run -it --privileged --network=host --name eda-dind \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add $(stat -c '%g' /var/run/docker.sock) \
  eda-wsl
```

## Uninstallation

```powershell
wsl --unregister EDA
```
