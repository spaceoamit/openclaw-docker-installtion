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

## Quick Reference

### Get Gateway Token
```bash
grep OPENCLAW_GATEWAY_TOKEN .env | cut -d'=' -f2
```

### Telegram Pairing (after setup)
```bash
# 1. Message your bot on Telegram (send /start)

# 2. List pending pairing requests
docker compose run --rm openclaw-cli pairing list

# 3. Approve using the code from the list
docker compose run --rm openclaw-cli pairing approve telegram <CODE>
```

### Common Commands
```bash
docker compose up -d                              # Start gateway
docker compose down                               # Stop gateway
docker compose logs -f openclaw-gateway           # View logs
docker compose run --rm openclaw-cli status       # Check status
curl http://127.0.0.1:18789/healthz               # Health check
```

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

1. **Start the gateway** (if not already running):

   ```bash
   docker compose up -d
   ```

2. **Message your Telegram bot** to initiate pairing (send any message like `/start`)

3. **Approve the pairing** via CLI:

   ```bash
   # Option 1: Using docker compose run
   docker compose run --rm openclaw-cli pairing list

   # Option 2: Exec into the running container
   docker exec -it $(docker compose ps -q openclaw-gateway) bash
   openclaw pairing list
   ```

   You'll see pending pairing requests like:
   ```
   ┌──────────┬─────────────────┬─────────────────────────────────────┬──────────────────────────┐
   │ Code     │ telegramUserId  │ Meta                                │ Requested                │
   ├──────────┼─────────────────┼─────────────────────────────────────┼──────────────────────────┤
   │ ABC123XY │ 1234567890      │ {"firstName":"John","lastName":"D"} │ 2026-03-13T11:32:58.000Z │
   └──────────┴─────────────────┴─────────────────────────────────────┴──────────────────────────┘
   ```

4. **Approve the request** using the code:

   ```bash
   # Using docker compose run
   docker compose run --rm openclaw-cli pairing approve telegram ABC123XY

   # Or if inside the container
   openclaw pairing approve telegram ABC123XY
   ```

5. **Start chatting** with your bot on Telegram!

### Note on Warning Messages

You may see warning messages like:
```
Failed to read config at /home/node/.openclaw/openclaw.json ReferenceError: Cannot access 'ANTHROPIC_MODEL_ALIASES' before initialization
```

These can be safely ignored — commands will still execute successfully.

### Useful Commands

```bash
# View logs
docker compose logs -f openclaw-gateway

# Check gateway health
curl http://127.0.0.1:18789/healthz

# Check status
docker compose run --rm openclaw-cli status

# Run doctor diagnostics
docker compose run --rm openclaw-cli doctor

# List paired users
docker compose run --rm openclaw-cli pairing list

# Enter container shell for multiple commands
docker exec -it $(docker compose ps -q openclaw-gateway) bash

# Restart gateway
docker compose restart openclaw-gateway

# Stop everything
docker compose down

# Stop and delete all data
docker compose down -v
```

## Storage

All data is stored in Docker-managed named volumes:

- `openclaw_config` — configuration files
- `openclaw_workspace` — workspace data

Nothing is stored on your host filesystem.

## Troubleshooting

### Group messages not working

If you see this warning:
```
channels.telegram.groupPolicy is "allowlist" but groupAllowFrom (and allowFrom) is empty — all group messages will be silently dropped.
```

This means the bot won't respond to group chats by default. To enable group support, run:

```bash
docker compose run --rm openclaw-cli config set channels.telegram.groupPolicy open
```

Or add specific group IDs to the allowlist:

```bash
docker compose run --rm openclaw-cli config set channels.telegram.groupAllowFrom '["<group_id>"]'
```

### Gateway not responding

```bash
# Check if container is running
docker compose ps

# Check health status
curl http://127.0.0.1:18789/healthz

# View logs for errors
docker compose logs -f openclaw-gateway

# Restart the gateway
docker compose restart openclaw-gateway
```

### Reset everything

To completely reset and start fresh:

```bash
docker compose down -v
./setup.sh
```
