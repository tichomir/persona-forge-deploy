# PersonaForge — Installer

The one-command installer for **PersonaForge**. This repo is public and contains
**only** the install script — no source code, no secrets. The application source
and the container images are private.

## Prerequisites

1. **A container engine + Compose.** Podman is recommended (daemonless, rootless,
   no Docker Desktop license). You need **`podman-compose`** alongside `podman`
   (or Docker with Compose).
   - **macOS:**
     ```bash
     brew install podman podman-compose
     podman machine init && podman machine start
     ```
   - **Linux:** install `podman` + `podman-compose` from your distro (or `pip3 install podman-compose`).
   - Docker alternative: install Docker Desktop (it includes Compose) and start it.
2. **Access** — ask the maintainer to add you as a **collaborator** (this grants you image-pull access).
3. **A GitHub token** with the **`read:packages`** scope:
   GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → check `read:packages`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/tichomir/persona-forge-deploy/main/install.sh | GHCR_TOKEN=<your-token> sh
```

Windows (PowerShell):

```powershell
$env:GHCR_TOKEN="<your-token>"; irm https://raw.githubusercontent.com/tichomir/persona-forge-deploy/main/install.ps1 | iex
```

That's it. The installer logs in to the registry, pulls the prebuilt images, and
starts everything on Docker/Podman-managed **named volumes** — nothing is written
to your filesystem outside the container engine. Then:

- Open **http://localhost:3000**
- Paste your **Anthropic API key** in the first-run wizard.

## Manage it

The installer adds a `personaforge` command:

```bash
personaforge start      # start the stack
personaforge stop       # stop it
personaforge update     # pull the latest images and restart
personaforge logs       # follow logs
personaforge status     # container status
```

## Notes

- **Updates:** `personaforge update` (or re-run the installer) pulls the latest images.
- **Your data** lives in named volumes (`podman volume ls | grep pf_` / `docker volume ls`) and survives restarts and updates.
- **Pin a version:** `PF_VERSION=v0.1.0 personaforge update`.
- **Trouble pulling images?** Your token needs `read:packages` and your account
  must be a collaborator. Re-run after `podman login ghcr.io` / `docker login ghcr.io`.
- **"Cannot connect to the Docker daemon" on a Podman box?** Make sure
  `podman-compose` is installed and the Podman machine is running
  (`podman machine start`). The installer points Compose at Podman's socket
  automatically, but it still needs a compose provider present.
