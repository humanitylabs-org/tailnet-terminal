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
  bash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

as_root cp /tmp/web-terminal.service /etc/systemd/system/web-terminal.service
rm -f /tmp/web-terminal.service

as_root systemctl daemon-reload
as_root systemctl enable --now web-terminal.service
systemctl is-active --quiet web-terminal.service || fail "web-terminal.service failed to start"

tailscale serve --bg --https=443 --set-path=/terminal http://127.0.0.1:7681 >/dev/null

DNS_NAME="$(tailscale status --self --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName", "").rstrip("."))' 2>/dev/null || true)"
if [[ -n "$DNS_NAME" ]]; then
  echo
  ok "Tailnet Terminal ready"
  echo "URL: https://${DNS_NAME}/terminal"
else
  ok "Tailnet Terminal ready"
  echo "URL: https://<this-device>.ts.net/terminal"
fi
