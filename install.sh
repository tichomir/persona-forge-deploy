#!/bin/sh
# ── PersonaForge installer (Podman-first; Docker also works) ─────────────────
#
#   curl -fsSL <this-url> | GHCR_TOKEN=<github-token> sh
#
# One command. No compose file to download, no data folder to create — the
# compose is embedded below and all storage is Docker/Podman-managed named
# volumes. The only input is GHCR_TOKEN (a GitHub token with read:packages,
# from an account that's a collaborator on the repo). Your Anthropic key goes
# in the first-run wizard in the browser, never on the command line.
#
# AUTO-GENERATED from docker-compose.release.yml by scripts/gen_installer.py —
# do not edit the embedded compose by hand; run the generator.
set -eu

REGISTRY="${PF_REGISTRY:-ghcr.io/tichomir}"
VERSION="${PF_VERSION:-latest}"
HOME_DIR="${PERSONAFORGE_HOME:-$HOME/.personaforge}"
PORT="${PORT:-3000}"
GHCR_USER="${GHCR_USER:-tichomir}"

say()  { printf '\033[1;36m▸ %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# 1. Container engine — Podman preferred (daemonless, rootless, no Desktop license)
if command -v podman >/dev/null 2>&1; then
    ENGINE=podman
    # Point docker-compatible compose providers at Podman's own socket, so a
    # docker-compose provider doesn't try (and fail) to reach a Docker daemon
    # — the classic "Cannot connect to the Docker daemon" error on Podman boxes.
    _sock=$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)
    if [ -n "$_sock" ]; then
        case "$_sock" in
            unix://*|npipe://*) export DOCKER_HOST="$_sock" ;;
            *) export DOCKER_HOST="unix://$_sock" ;;
        esac
    fi
    # Prefer podman-compose (talks to Podman directly); the `podman compose`
    # wrapper's provider varies by machine and may pick docker-compose.
    if command -v podman-compose >/dev/null 2>&1; then COMPOSE="podman-compose"
    elif podman compose version >/dev/null 2>&1; then COMPOSE="podman compose"
    else die "Podman found but no compose provider. Install it:  pip3 install podman-compose"
    fi
elif command -v docker >/dev/null 2>&1; then
    ENGINE=docker
    docker compose version >/dev/null 2>&1 && COMPOSE="docker compose" || COMPOSE="docker-compose"
else
    die "No container engine found. Install Podman (recommended: https://podman.io) or Docker, then re-run."
fi
say "Using $ENGINE ($COMPOSE)"

# 2. Log in to GHCR (images are private)
[ -n "${GHCR_TOKEN:-}" ] || die "Set GHCR_TOKEN to a GitHub token with the read:packages scope. e.g.  curl -fsSL <url> | GHCR_TOKEN=ghp_xxx sh"
say "Logging in to ghcr.io as $GHCR_USER"
printf '%s' "$GHCR_TOKEN" | $ENGINE login ghcr.io -u "$GHCR_USER" --password-stdin \
    || die "Registry login failed. Check the token (read:packages) and that the account is a collaborator."

# 3. Write the embedded compose (no download, no host data dir — named volumes)
mkdir -p "$HOME_DIR"
cat > "$HOME_DIR/docker-compose.release.yml" <<'COMPOSE_EOF'
# ── PersonaForge — RELEASE compose (prebuilt images, Docker-managed storage) ─
#
# A proper containerized product: pull prebuilt images from GHCR, and let Docker
# own ALL persistent state via NAMED VOLUMES. There is nothing to create on the
# host — no data folder, no config file, no source tree.
#
# Install on any machine:
#   echo <TOKEN> | docker login ghcr.io -u <github-username> --password-stdin
#   docker compose -f docker-compose.release.yml up -d
#   open http://localhost:3000        # paste your Anthropic key in the wizard
#
# Update:   docker compose -f docker-compose.release.yml pull && up -d
# Backup:   docker run --rm -v personaforge_pf_personas:/d -v "$PWD":/b alpine \
#               tar czf /b/personas.tgz -C /d .    (repeat per volume)
#
# Overridable: PF_REGISTRY (default ghcr.io/tichomir), PF_VERSION (default latest),
#              PORT (GUI host port, default 3000).
#
# On first boot the API container seeds the built-in roles/skills/tools and an
# empty config into the volumes. The data roots are relocated to /data/* (env
# vars below) so the volume mounts never shadow the baked Python source.
# ────────────────────────────────────────────────────────────────────────────

x-config-env: &config-path PERSONAFORGE_CONFIG_PATH=/data/config/personaforge.config.json

services:

  api:
    image: ${PF_REGISTRY:-ghcr.io/tichomir}/persona-forge-api:${PF_VERSION:-latest}
    volumes:
      - pf_config:/data/config                       # personaforge.config.json (shared)
      - pf_personas:/data/personas                   # persona data + registry
      - pf_skills:/data/skill_library                # roles/tools/skills catalogue
      - pf_builder:/data/builder-memory              # builder action log
      - pf_knowledge:/app/knowledge
      - pf_pipeline_defs:/app/pipelines/definitions
      - pf_pipeline_runs:/app/pipelines/runs         # shared with runner
      - pf_roundtable_defs:/app/roundtables/definitions
      - pf_roundtable_runs:/app/roundtables/runs
      - pf_team_defs:/app/teams/definitions
      - pf_team_runs:/app/teams/runs
      - pf_survey_defs:/app/surveys/definitions
      - pf_survey_runs:/app/surveys/runs
      - pf_interview_defs:/app/interviews/definitions
      - pf_interview_runs:/app/interviews/runs
      - pf_scheduler:/app/scheduler/tasks
      - pf_multichat:/app/multi_chat/sessions
      - pf_valuepacks:/app/value_packs/manifests
      - pf_templates:/app/templates                  # shared with runner
      - pf_persona_git:/app/.persona-data.git
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - SPRINT_RUNNER_URL=${SPRINT_RUNNER_URL:-http://runner:8002}
      - MCP_WORKSPACE_URL=${MCP_WORKSPACE_URL:-http://mcp-google-workspace:8000/mcp}
      - PERSONAFORGE_PERSONAS_DIR=/data/personas
      - PERSONAFORGE_SKILL_DATA_DIR=/data/skill_library
      - PERSONAFORGE_BUILDER_MEMORY_DIR=/data/builder-memory
      - *config-path
    depends_on:
      - runner
      - mcp-google-workspace
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

  runner:
    image: ${PF_REGISTRY:-ghcr.io/tichomir}/persona-forge-runner:${PF_VERSION:-latest}
    volumes:
      # Claude Code CLI authenticates via ANTHROPIC_API_KEY (read from the shared
      # config volume) — no host ~/.claude needed.
      - pf_config:/data/config
      - pf_projects:/home/runner/coding              # agile-team build workspace
      - pf_templates:/app/templates
      - pf_pipeline_runs:/app/data/pipelines/runs:ro
      - pf_figma_cache:/figma-cache:ro
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - SPRINT_RUNNER_PORT=8002
      - CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000
      - *config-path
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8002/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s

  mcp-google-workspace:
    image: ${PF_REGISTRY:-ghcr.io/tichomir}/persona-forge-mcp-google-workspace:${PF_VERSION:-latest}
    ports:
      # one-time Google OAuth callback. Host port overridable (PF_MCP_OAUTH_PORT)
      # so a throwaway/second stack can avoid clashing with a running instance.
      - "127.0.0.1:${PF_MCP_OAUTH_PORT:-8000}:8000"
    volumes:
      - pf_config:/data/config
      - pf_mcp_tokens:/root/.google_workspace_mcp
    environment:
      - HOST=0.0.0.0
      - PORT=8000
      - *config-path
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s

  mcp-figma:
    image: ${PF_REGISTRY:-ghcr.io/tichomir}/persona-forge-mcp-figma:${PF_VERSION:-latest}
    volumes:
      - pf_config:/data/config:ro
      - pf_figma_cache:/figma-cache
    environment:
      - PORT=8005
      - FRAMELINK_HOST=0.0.0.0
      - IMAGE_DIR=/figma-cache
      - *config-path
    restart: unless-stopped

  gui:
    image: ${PF_REGISTRY:-ghcr.io/tichomir}/persona-forge-gui:${PF_VERSION:-latest}
    ports:
      - "${PORT:-3000}:80"
    depends_on:
      - api
    restart: unless-stopped

# Docker-managed named volumes — created automatically on first `up`.
# Nothing on the host to pre-create. Inspect with `docker volume ls`.
volumes:
  pf_config:
  pf_personas:
  pf_skills:
  pf_builder:
  pf_knowledge:
  pf_pipeline_defs:
  pf_pipeline_runs:
  pf_roundtable_defs:
  pf_roundtable_runs:
  pf_team_defs:
  pf_team_runs:
  pf_survey_defs:
  pf_survey_runs:
  pf_interview_defs:
  pf_interview_runs:
  pf_scheduler:
  pf_multichat:
  pf_valuepacks:
  pf_templates:
  pf_persona_git:
  pf_projects:
  pf_figma_cache:
  pf_mcp_tokens:
COMPOSE_EOF

# 4. Pull + start
cd "$HOME_DIR"
say "Pulling images (first time may take a minute)…"
PF_REGISTRY="$REGISTRY" PF_VERSION="$VERSION" $COMPOSE -f docker-compose.release.yml pull
say "Starting PersonaForge…"
PF_REGISTRY="$REGISTRY" PF_VERSION="$VERSION" PORT="$PORT" $COMPOSE -f docker-compose.release.yml up -d

# 5. Install the `personaforge` lifecycle command (best-effort)
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/personaforge" <<PF_CLI_EOF
#!/bin/sh
exec env PERSONAFORGE_HOME="$HOME_DIR" PF_REGISTRY="$REGISTRY" PF_VERSION="$VERSION" PORT="$PORT" \\
    sh -c 'cd "\$PERSONAFORGE_HOME" && case "\${1:-help}" in
      start|up) $COMPOSE -f docker-compose.release.yml up -d ;;
      stop|down) $COMPOSE -f docker-compose.release.yml down ;;
      update) $COMPOSE -f docker-compose.release.yml pull && $COMPOSE -f docker-compose.release.yml up -d ;;
      logs) shift; $COMPOSE -f docker-compose.release.yml logs -f "\$@" ;;
      status|ps) $COMPOSE -f docker-compose.release.yml ps ;;
      *) echo "personaforge: start|stop|update|logs|status" ;;
    esac' personaforge "\$@"
PF_CLI_EOF
chmod +x "$BIN_DIR/personaforge" 2>/dev/null || true

# Make sure ~/.local/bin is on PATH so `personaforge` works without a full path.
# If it isn't, add it to the user's shell rc (idempotent) so new shells pick it
# up, and below we tell them how to activate it in the current shell too.
PF_RC=""
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;  # already on PATH — nothing to do
  *)
    case "${SHELL:-}" in
      *zsh)  PF_RC="$HOME/.zshrc" ;;
      *bash) PF_RC="$HOME/.bashrc" ;;
      *)     PF_RC="$HOME/.profile" ;;
    esac
    PF_PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
    if ! grep -qsF "$PF_PATH_LINE" "$PF_RC" 2>/dev/null; then
      printf '\n# Added by the PersonaForge installer\n%s\n' "$PF_PATH_LINE" >> "$PF_RC" 2>/dev/null || true
    fi
    ;;
esac

say "PersonaForge is starting at http://localhost:$PORT"
say "Open it and paste your Anthropic API key in the wizard."
say "Manage it anytime with:  personaforge start | stop | update | logs | status"
if [ -n "$PF_RC" ]; then
  say "Note: ~/.local/bin wasn't on your PATH — added it to $PF_RC."
  say "  Open a NEW terminal, or run now:  export PATH=\"\$HOME/.local/bin:\$PATH\""
  say "  Until then, use the full path:    $BIN_DIR/personaforge status"
fi
( command -v open >/dev/null 2>&1 && open "http://localhost:$PORT" ) \
    || ( command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:$PORT" ) || true
