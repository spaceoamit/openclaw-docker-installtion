#!/usr/bin/env bash
set -euo pipefail

# ─── OpenClaw Docker Setup (Named Volumes — fully isolated) ─────────
# All data stays inside Docker-managed volumes. Nothing touches ~/
# After setup, just message the Telegram bot and approve pairing.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ─── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# ─── Load .env ───────────────────────────────────────────────────────
load_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    else
        error ".env file not found. Fill in your keys in .env and re-run."
        exit 1
    fi
}

# ─── Validate required keys ─────────────────────────────────────────
validate_keys() {
    local missing=0

    if [ -z "${ANTHROPIC_API_KEY:-}" ] || [ "$ANTHROPIC_API_KEY" = "sk-ant-PASTE_YOUR_KEY_HERE" ]; then
        error "ANTHROPIC_API_KEY is not set in .env"
        error "Get your key from: https://console.anthropic.com/settings/keys"
        missing=1
    fi

    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ "$TELEGRAM_BOT_TOKEN" = "PASTE_YOUR_BOT_TOKEN_HERE" ]; then
        error "TELEGRAM_BOT_TOKEN is not set in .env"
        error "Get your token from @BotFather on Telegram"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        echo ""
        error "Please fill in the required values in .env and re-run this script."
        exit 1
    fi

    ok "Anthropic API key and Telegram bot token found."
}

# ─── Check prerequisites ────────────────────────────────────────────
check_prereqs() {
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed. Please install Docker Desktop or Docker Engine."
        exit 1
    fi

    if ! docker compose version &>/dev/null 2>&1; then
        error "Docker Compose v2 is required. Please update Docker."
        exit 1
    fi

    if ! docker info &>/dev/null 2>&1; then
        error "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    ok "Docker and Docker Compose v2 detected."
}

# ─── Generate gateway token if not set ───────────────────────────────
generate_token() {
    if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ] || [ "$OPENCLAW_GATEWAY_TOKEN" = "CHANGE_ME_GENERATE_A_TOKEN" ]; then
        local token
        token="$(openssl rand -hex 32)"
        info "Generated new gateway token."

        if [ -f "$SCRIPT_DIR/.env" ]; then
            if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$SCRIPT_DIR/.env"; then
                sed -i.bak "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=${token}|" "$SCRIPT_DIR/.env"
                rm -f "$SCRIPT_DIR/.env.bak"
            else
                echo "OPENCLAW_GATEWAY_TOKEN=${token}" >> "$SCRIPT_DIR/.env"
            fi
        fi

        export OPENCLAW_GATEWAY_TOKEN="$token"
        ok "Token written to .env"
    else
        ok "Using existing gateway token from .env"
    fi
}

# ─── Pull image ─────────────────────────────────────────────────────
prepare_image() {
    local image="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}"

    info "Pulling image: $image ..."
    docker pull "$image"
    ok "Image ready: $image"
}

# ─── Create named volumes and seed config ────────────────────────────
seed_config() {
    local image="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}"

    # Create volumes if they don't exist (docker compose up would do this,
    # but we need them before starting so we can seed the config file)
    docker volume create openclaw_config   >/dev/null 2>&1 || true
    docker volume create openclaw_workspace >/dev/null 2>&1 || true

    # Check if config already exists inside the volume
    local has_config
    has_config=$(docker run --rm \
        -v openclaw_config:/mnt/config \
        --entrypoint sh \
        "$image" \
        -c '[ -f /mnt/config/openclaw.json ] && echo "yes" || echo "no"')

    if [ "$has_config" = "yes" ]; then
        warn "openclaw.json already exists in the volume — skipping seed."
        return
    fi

    info "Seeding openclaw.json into Docker volume..."

    # Use a temporary container to write the config into the named volume
    # Mount BOTH volumes so we can fix workspace ownership too
    docker run --rm \
        -v openclaw_config:/mnt/config \
        -v openclaw_workspace:/mnt/workspace \
        --user root \
        --entrypoint sh \
        "$image" \
        -c 'mkdir -p /mnt/config/identity \
                     /mnt/config/agents/main/agent \
                     /mnt/config/agents/main/sessions && \
chown -R 1000:1000 /mnt/workspace && \
cat > /mnt/config/openclaw.json << '"'"'EOF'"'"'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan",
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "enabled": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5",
        "fallbacks": ["anthropic/claude-haiku-4-5"]
      },
      "workspace": "/home/node/.openclaw/workspace",
      "timeoutSeconds": 600,
      "contextTokens": 200000
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "historyLimit": 50,
      "replyToMode": "first",
      "linkPreview": true,
      "streaming": "partial",
      "mediaMaxMb": 5,
      "actions": {
        "reactions": true,
        "sendMessage": true
      }
    }
  },
  "logging": {
    "level": "info"
  }
}
EOF
chown -R 1000:1000 /mnt/config'

    ok "Config seeded into openclaw_config volume."
}

# ─── Start gateway ──────────────────────────────────────────────────
start_gateway() {
    info "Starting OpenClaw gateway..."
    docker compose up -d openclaw-gateway
    ok "Gateway starting up."

    info "Waiting for gateway to become healthy..."
    local retries=0
    local max_retries=30
    while [ $retries -lt $max_retries ]; do
        if docker compose exec openclaw-gateway node -e \
            "fetch('http://127.0.0.1:18789/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" \
            2>/dev/null; then
            ok "Gateway is healthy!"
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done

    if [ $retries -ge $max_retries ]; then
        warn "Gateway did not become healthy in time. Check logs with:"
        warn "  docker compose logs openclaw-gateway"
    fi
}

# ─── Print summary ──────────────────────────────────────────────────
print_summary() {
    local port="${OPENCLAW_GATEWAY_PORT:-18789}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "${GREEN}OpenClaw is running!${NC}\n"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Control UI:   http://127.0.0.1:${port}/"
    echo "  Health check: curl -fsS http://127.0.0.1:${port}/healthz"
    echo ""
    echo "  Gateway token (paste into Control UI Settings):"
    echo "    ${OPENCLAW_GATEWAY_TOKEN}"
    echo ""
    printf "  ${CYAN}Telegram pairing:${NC}\n"
    echo "    1. Message your bot on Telegram"
    echo "    2. The bot will reply with a pairing code"
    echo "    3. Approve the pairing in the Control UI or run:"
    echo "       docker compose run --rm openclaw-cli devices list"
    echo "       docker compose run --rm openclaw-cli devices approve <ID>"
    echo ""
    printf "  ${YELLOW}Storage (fully isolated):${NC}\n"
    echo "    Config:    docker volume: openclaw_config"
    echo "    Workspace: docker volume: openclaw_workspace"
    echo "    Nothing is stored on your Mac's filesystem."
    echo ""
    echo "  Useful commands:"
    echo "    docker compose logs -f openclaw-gateway     # View logs"
    echo "    docker compose run --rm openclaw-cli status  # Check status"
    echo "    docker compose down                         # Stop everything"
    echo "    docker compose down -v                      # Stop + delete all data"
    echo "    docker compose restart openclaw-gateway     # Restart gateway"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
    echo ""
    printf "${CYAN}OpenClaw Docker Setup (Isolated Named Volumes)${NC}\n"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    load_env
    validate_keys
    check_prereqs
    generate_token
    prepare_image
    seed_config
    start_gateway
    print_summary
}

main "$@"
