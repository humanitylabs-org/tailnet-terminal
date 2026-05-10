#!/usr/bin/env bash
set -euo pipefail

ok() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

need_cmd() {
  local c="$1"
  if command -v "$c" >/dev/null 2>&1; then
    ok "$c: $(command -v "$c")"
  else
    fail "Missing required command: $c"
  fi
}

echo "Tailnet Terminal prereq check"

need_cmd tailscale
if tailscale status >/dev/null 2>&1; then
  ok "tailscale connected"
else
  fail "tailscale is not connected. Run: tailscale up"
fi

need_cmd ttyd

echo
ok "All required checks passed"
