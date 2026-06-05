# ── PersonaForge installer (Windows / PowerShell — Podman-first) ─────────────
#
#   $env:GHCR_TOKEN="<github-token>"; irm <this-url> | iex
#
# No compose file to download, no data folder — the compose is embedded and all
# storage is named volumes. AUTO-GENERATED from docker-compose.release.yml by
# scripts/gen_installer.py — do not edit the embedded compose by hand.

$ErrorActionPreference = "Stop"
$Registry = if ($env:PF_REGISTRY) { $env:PF_REGISTRY } else { "ghcr.io/tichomir" }
$Version  = if ($env:PF_VERSION)  { $env:PF_VERSION }  else { "latest" }
$HomeDir  = if ($env:PERSONAFORGE_HOME) { $env:PERSONAFORGE_HOME } else { Join-Path $env:USERPROFILE ".personaforge" }
$Port     = if ($env:PORT) { $env:PORT } else { "3000" }
$GhcrUser = if ($env:GHCR_USER) { $env:GHCR_USER } else { "tichomir" }

function Say($m) { Write-Host "▸ $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

# 1. Engine — Podman preferred
if (Get-Command podman -ErrorAction SilentlyContinue) {
    $Engine = "podman"; $Compose = "podman compose"
} elseif (Get-Command docker -ErrorAction SilentlyContinue) {
    $Engine = "docker"; $Compose = "docker compose"
} else { Die "No container engine found. Install Podman (recommended) or Docker." }
Say "Using $Engine"

# 2. GHCR login
if (-not $env:GHCR_TOKEN) { Die "Set `$env:GHCR_TOKEN to a GitHub token with read:packages." }
Say "Logging in to ghcr.io as $GhcrUser"
$env:GHCR_TOKEN | & $Engine login ghcr.io -u $GhcrUser --password-stdin
if ($LASTEXITCODE -ne 0) { Die "Registry login failed (token / collaborator?)." }

# 3. Write embedded compose
New-Item -ItemType Directory -Force -Path $HomeDir | Out-Null
$composePath = Join-Path $HomeDir "docker-compose.release.yml"
@'
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
      - "127.0.0.1:8000:8000"                        # one-time Google OAuth callback
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
'@ | Out-File -FilePath $composePath -Encoding utf8

# 4. Pull + start
Push-Location $HomeDir
$env:PF_REGISTRY = $Registry; $env:PF_VERSION = $Version; $env:PORT = $Port
Say "Pulling images…"
Invoke-Expression "$Compose -f docker-compose.release.yml pull"
Say "Starting PersonaForge…"
Invoke-Expression "$Compose -f docker-compose.release.yml up -d"
Pop-Location

Say "PersonaForge is starting at http://localhost:$Port — paste your Anthropic key in the wizard."
Start-Process "http://localhost:$Port"
