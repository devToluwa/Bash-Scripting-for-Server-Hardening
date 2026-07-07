#!/bin/bash

set -euo pipefai;

echo "[1/8] Updating system packages..."
apt update && apt upgrade -y

echo "[2/8] Disabling unnecessary services..."
systemctl disable --now bluethooth avahi-daemon cups 2>/dev/null || true

echo "[3/8] Hardening SSH configuration..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd