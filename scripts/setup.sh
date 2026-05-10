#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ok() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "Root privileges are required and sudo is not installed."
  fi
}

"$APP_DIR/scripts/prereq-check.sh"

TERMINAL_UI_DIR="/usr/local/share/tailnet-terminal"
TERMINAL_INDEX="$TERMINAL_UI_DIR/index.html"
BOOTSTRAP_PORT="17681"

mkdir -p "$TERMINAL_UI_DIR"
install -m 0644 "$APP_DIR/icon-192.png" "$TERMINAL_UI_DIR/icon-192.png"
install -m 0644 "$APP_DIR/icon-512.png" "$TERMINAL_UI_DIR/icon-512.png"
install -m 0644 "$APP_DIR/apple-touch-icon.png" "$TERMINAL_UI_DIR/apple-touch-icon.png"
cat >"$TERMINAL_UI_DIR/manifest.webmanifest" <<'JSON'
{
  "name": "Tailnet Terminal",
  "short_name": "Terminal",
  "id": "/terminal/",
  "start_url": "/terminal/",
  "scope": "/terminal/",
  "display": "standalone",
  "background_color": "#0B0B0D",
  "theme_color": "#0B0B0D",
  "icons": [
    { "src": "/terminal/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable" },
    { "src": "/terminal/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
  ]
}
JSON

# Generate a version-matched ttyd index and patch title.
BOOT_PID=""
cleanup_bootstrap() {
  if [[ -n "$BOOT_PID" ]] && kill -0 "$BOOT_PID" 2>/dev/null; then
    kill "$BOOT_PID" 2>/dev/null || true
    sleep 0.5
    kill -9 "$BOOT_PID" 2>/dev/null || true
  fi
}
trap cleanup_bootstrap EXIT

/usr/local/bin/ttyd --interface 127.0.0.1 --port "$BOOTSTRAP_PORT" --writable bash >/tmp/tailnet-terminal-bootstrap.log 2>&1 &
BOOT_PID="$!"
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:${BOOTSTRAP_PORT}" >/tmp/tailnet-terminal-index.raw.html 2>/dev/null; then
    break
  fi
  sleep 0.2
done

if [[ ! -s /tmp/tailnet-terminal-index.raw.html ]]; then
  fail "Failed to bootstrap ttyd index.html for title patching"
fi

python3 - <<'PY'
from pathlib import Path
src = Path('/tmp/tailnet-terminal-index.raw.html').read_text(encoding='utf-8')
out = src.replace('<title>ttyd - Terminal</title>', '<title>Tailnet Terminal</title>', 1)
insert = '\n<link rel="manifest" href="/terminal/manifest.webmanifest">\n<link rel="icon" type="image/png" sizes="192x192" href="/terminal/icon-192.png">\n<link rel="apple-touch-icon" href="/terminal/apple-touch-icon.png">\n'
if '/terminal/manifest.webmanifest' not in out:
    out = out.replace('</head>', insert + '</head>', 1)
Path('/tmp/tailnet-terminal-index.custom.html').write_text(out, encoding='utf-8')
PY

as_root install -m 0644 /tmp/tailnet-terminal-index.custom.html "$TERMINAL_INDEX"
rm -f /tmp/tailnet-terminal-index.raw.html /tmp/tailnet-terminal-index.custom.html
cleanup_bootstrap
BOOT_PID=""

cat <<'EOF' >/tmp/web-terminal.service
[Unit]
Description=Web Terminal (ttyd via Tailscale)
After=network-online.target

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=TERM=xterm-256color
ExecStart=/usr/local/bin/ttyd \
  --interface 127.0.0.1 \
  --port 7681 \
  --writable \
  --max-clients 3 \
  --ping-interval 30 \
  --index /usr/local/share/tailnet-terminal/index.html \
  bash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

as_root cp /tmp/web-terminal.service /etc/systemd/system/web-terminal.service
rm -f /tmp/web-terminal.service

as_root systemctl daemon-reload
as_root systemctl enable web-terminal.service
as_root systemctl restart web-terminal.service
systemctl is-active --quiet web-terminal.service || fail "web-terminal.service failed to start"

tailscale serve --bg --https=443 --set-path=/terminal http://127.0.0.1:7681 >/dev/null
tailscale serve --bg --https=443 --set-path=/terminal/manifest.webmanifest "$TERMINAL_UI_DIR/manifest.webmanifest" >/dev/null
tailscale serve --bg --https=443 --set-path=/terminal/apple-touch-icon.png "$TERMINAL_UI_DIR/apple-touch-icon.png" >/dev/null
tailscale serve --bg --https=443 --set-path=/terminal/icon-192.png "$TERMINAL_UI_DIR/icon-192.png" >/dev/null
tailscale serve --bg --https=443 --set-path=/terminal/icon-512.png "$TERMINAL_UI_DIR/icon-512.png" >/dev/null

DNS_NAME="$(tailscale status --self --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName", "").rstrip("."))' 2>/dev/null || true)"
if [[ -n "$DNS_NAME" ]]; then
  echo
  ok "Tailnet Terminal ready"
  echo "URL: https://${DNS_NAME}/terminal"
else
  ok "Tailnet Terminal ready"
  echo "URL: https://<this-device>.ts.net/terminal"
fi
