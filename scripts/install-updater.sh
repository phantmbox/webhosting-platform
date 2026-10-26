#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "[FOUT] Gebruik sudo ./scripts/install-updater.sh"; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update-server.sh"
SSH_KEY="/home/phantmbox/.ssh/webhosting_platform"
[[ -r "$SSH_KEY" ]] || { echo "[FOUT] SSH-sleutel ontbreekt: $SSH_KEY"; exit 1; }

install -o root -g root -m 0755 "$SRC" /usr/local/sbin/webhosting-update
install -d -o root -g adm -m 0750 /var/log/webhosting-platform

cat > /etc/systemd/system/webhosting-github-sync.service <<'UNIT'
[Unit]
Description=Webhosting Platform GitHub sync and safe deploy
After=network-online.target mysql.service apache2.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/webhosting-update
User=root
Group=root
Nice=10
UNIT

cat > /etc/systemd/system/webhosting-github-sync.timer <<'UNIT'
[Unit]
Description=Check GitHub for Webhosting Platform updates

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=20s
Persistent=true
Unit=webhosting-github-sync.service

[Install]
WantedBy=timers.target
UNIT

cat > /etc/sudoers.d/webhosting-update <<'SUDO'
phantmbox ALL=(root) NOPASSWD: /usr/local/sbin/webhosting-update
SUDO
chmod 0440 /etc/sudoers.d/webhosting-update
visudo -cf /etc/sudoers.d/webhosting-update >/dev/null
systemctl daemon-reload
systemctl enable --now webhosting-github-sync.timer
systemctl start webhosting-github-sync.service
systemctl is-active --quiet webhosting-github-sync.timer

echo "Automatische GitHub-sync actief (elke 2 minuten)."
echo "Status: systemctl status webhosting-github-sync.timer"
echo "Log:    /var/log/webhosting-platform/deploy.log"
