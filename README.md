# Tailnet Terminal

Dedicated web terminal app exposed at `/terminal` on your Tailscale HTTPS host.

## What it sets up

- `web-terminal.service` (systemd)
- `ttyd` bound to `127.0.0.1:7681`
- Tailscale path route:
  - `/terminal` -> `http://127.0.0.1:7681`

## Usage

```bash
./scripts/prereq-check.sh
./scripts/setup.sh
./scripts/status.sh
```

URL format:

```text
https://<this-device>.ts.net/terminal
```
