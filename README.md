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
4. **Claude access — ONE of the two** (both fully supported, switchable anytime):
   - **A Claude Code seat** *(no API key — recommended when your organisation
     restricts API keys)*. You'll need [Claude Code](https://docs.claude.com/en/docs/claude-code)
     installed and signed in on your machine — used once, to mint a token (step below).
   - **An Anthropic API key** from [console.anthropic.com](https://console.anthropic.com).

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
- Connect Claude under **Settings → Integrations → Anthropic** — pick one:

### Option A — Claude Code seat (no API key)

1. On the machine where you're signed in to Claude Code, run:
   ```bash
   claude setup-token
   ```
2. Copy the token it prints (starts with `sk-ant-oat…`).
3. In PersonaForge: **Settings → Anthropic → Claude access** → paste it →
   **Save token**. (It's stored write-only and never included in backups.)
4. Apply it to the runner:
   ```bash
   personaforge stop && personaforge start
   ```

The card's **Active** chip should now read *Claude Code seat*.

### Option B — Anthropic API key

Paste your `sk-ant-api…` key in the **Anthropic API Key** card on the same page.

Both can coexist — the **Mode** selector on the Claude access card decides:
**Auto** (default) uses the seat token when present, otherwise the key;
**Seat only** / **API key only** force one side (the latter is the instant
rollback switch). Details: the in-app guide *Claude access*.

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
- **Seat-mode notes:** your Claude Code seat has 5-hour usage windows (not
  metered billing); very heavy parallel workloads may briefly throttle. Group
  chat replies arrive as whole messages (no word-by-word streaming). Rotating
  the seat token: mint a new one with `claude setup-token`, paste it in
  Settings, `personaforge stop && personaforge start`.
- **Your data** lives in named volumes (`podman volume ls | grep pf_` / `docker volume ls`) and survives restarts and updates.
- **Pin a version:** `PF_VERSION=v0.1.0 personaforge update`.
- **Trouble pulling images?** Your token needs `read:packages` and your account
  must be a collaborator. Re-run after `podman login ghcr.io` / `docker login ghcr.io`.
- **"Cannot connect to the Docker daemon" on a Podman box?** Make sure
  `podman-compose` is installed and the Podman machine is running
  (`podman machine start`). The installer points Compose at Podman's socket
  automatically, but it still needs a compose provider present.
