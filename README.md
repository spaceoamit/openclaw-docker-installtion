# OpenClaw Docker Installation

A Docker-based setup for running [OpenClaw](https://github.com/openclaw/openclaw) with Telegram bot integration.

## Prerequisites

- Docker Desktop or Docker Engine
- Docker Compose v2
- An [Anthropic API key](https://console.anthropic.com/settings/keys)
- A [Telegram Bot Token](https://t.me/BotFather)

## Quick Start

1. **Clone the repository**

   ```bash
   git clone https://github.com/spaceoamit/openclaw-docker-installtion.git
   cd openclaw-docker-installtion
   ```

2. **Create your `.env` file**

   ```bash
   cp .env.example .env
   ```

3. **Fill in your keys** in `.env`:

   - `ANTHROPIC_API_KEY` — your Claude API key
   - `TELEGRAM_BOT_TOKEN` — your Telegram bot token

4. **Run the setup script**

   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

   The script will:
   - Validate your API keys
   - Generate a gateway token (if not already set)
   - Pull the OpenClaw Docker image
   - Seed the configuration into Docker volumes
   - Start the gateway and wait for it to become healthy

## Configuration

All configuration is done through the `.env` file. See `.env.example` for available options.

| Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Your Anthropic/Claude API key |
| `TELEGRAM_BOT_TOKEN` | Yes | Your Telegram bot token from @BotFather |
| `OPENCLAW_GATEWAY_TOKEN` | No | Auto-generated if not set |
| `OPENCLAW_GATEWAY_BIND` | No | Network bind mode (default: `lan`) |
| `OPENCLAW_GATEWAY_PORT` | No | Gateway port (default: `18789`) |
| `OPENCLAW_BRIDGE_PORT` | No | Bridge port (default: `18790`) |

## Usage

After setup completes:

1. **Open the Control UI** at `http://127.0.0.1:18789/` and paste your gateway token in Settings.

2. **Message your Telegram bot** — the bot will reply with a pairing code.

3. **Approve the pairing** via Control UI or CLI:

   ```bash
   docker compose run --rm openclaw-cli devices list
   docker compose run --rm openclaw-cli devices approve <ID>
   ```

4. **Start chatting** with your bot on Telegram!

## Useful Commands

```bash
docker compose logs -f openclaw-gateway     # View logs
docker compose run --rm openclaw-cli status  # Check status
curl -fsS http://127.0.0.1:18789/healthz    # Health check
docker compose restart openclaw-gateway      # Restart gateway
docker compose down                          # Stop everything
docker compose down -v                       # Stop + delete all data
```

## Storage

All data is stored in Docker-managed named volumes:

- `openclaw_config` — configuration files
- `openclaw_workspace` — workspace data

Nothing is stored on your host filesystem.
