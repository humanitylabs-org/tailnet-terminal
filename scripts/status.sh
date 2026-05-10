#!/usr/bin/env bash
set -euo pipefail

echo "web-terminal.service"
systemctl is-active web-terminal.service
systemctl is-enabled web-terminal.service
systemctl show web-terminal.service -p Restart -p RestartUSec -p ActiveState -p SubState

echo

echo "tailscale route"
tailscale serve status | sed -n '1,80p'
