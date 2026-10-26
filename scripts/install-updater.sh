#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "[FOUT] Gebruik sudo ./scripts/install-updater.sh"; exit 1; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update-server.sh"
install -o root -g root -m 0755 "$SRC" /usr/local/sbin/webhosting-update
cat > /etc/sudoers.d/webhosting-update <<'SUDO'
phantmbox ALL=(root) NOPASSWD: /usr/local/sbin/webhosting-update
SUDO
chmod 0440 /etc/sudoers.d/webhosting-update
visudo -cf /etc/sudoers.d/webhosting-update >/dev/null
echo "Updater geïnstalleerd: sudo webhosting-update"
