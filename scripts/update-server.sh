#!/usr/bin/env bash
set -Eeuo pipefail

REPO="/opt/webhosting-platform"
APP="/opt/webhosting-admin"
BACKUP_ROOT="/srv/webhosting/backups/platform"
LOG_ROOT="/var/log/webhosting-platform"
SERVICE="webhosting-admin"
BRANCH="${BRANCH:-main}"
SSH_KEY="${SSH_KEY:-/home/phantmbox/.ssh/webhosting_platform}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$STAMP"
OLD_COMMIT=""
NEW_COMMIT=""

[[ $EUID -eq 0 ]] || { echo "[FOUT] Gebruik: sudo $0"; exit 1; }
[[ -d "$REPO/.git" ]] || { echo "[FOUT] Git repository ontbreekt: $REPO"; exit 1; }
[[ -r "$SSH_KEY" ]] || { echo "[FOUT] GitHub SSH-sleutel ontbreekt: $SSH_KEY"; exit 1; }
for cmd in node npm git curl mysql apache2ctl systemctl; do command -v "$cmd" >/dev/null || { echo "[FOUT] Commando ontbreekt: $cmd"; exit 1; }; done

mkdir -p "$BACKUP_ROOT" "$LOG_ROOT"
exec > >(tee -a "$LOG_ROOT/deploy.log") 2>&1
export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o IdentitiesOnly=yes -o BatchMode=yes"

OLD_COMMIT="$(git -C "$REPO" rev-parse HEAD)"
echo "[$(date -Is)] Controle GitHub main vanaf $OLD_COMMIT"
git -C "$REPO" fetch --quiet origin "$BRANCH"
NEW_COMMIT="$(git -C "$REPO" rev-parse "origin/$BRANCH")"

if [[ "$OLD_COMMIT" == "$NEW_COMMIT" ]]; then
  echo "[$(date -Is)] Geen update; server is actueel."
  exit 0
fi

rollback() {
  rc=$?
  trap - ERR
  echo "[ROLLBACK] Deploy van $NEW_COMMIT mislukt; $OLD_COMMIT wordt hersteld."
  if [[ -d "$BACKUP/app" ]]; then rm -rf "$APP"; cp -a "$BACKUP/app" "$APP"; fi
  [[ -f "$BACKUP/webhosting-admin.service" ]] && cp -a "$BACKUP/webhosting-admin.service" /etc/systemd/system/webhosting-admin.service
  [[ -f "$BACKUP/webhosting-admin.conf" ]] && cp -a "$BACKUP/webhosting-admin.conf" /etc/apache2/conf-available/webhosting-admin.conf
  git -C "$REPO" reset --hard "$OLD_COMMIT" || true
  systemctl daemon-reload || true
  apache2ctl configtest || true
  systemctl restart "$SERVICE" || true
  systemctl reload apache2 || true
  echo "[FOUT] Rollback uitgevoerd. Backup: $BACKUP"
  exit "$rc"
}
trap rollback ERR

echo "[1/7] Backup"
mkdir -p "$BACKUP"
[[ -d "$APP" ]] && cp -a "$APP" "$BACKUP/app"
[[ -f /etc/systemd/system/webhosting-admin.service ]] && cp -a /etc/systemd/system/webhosting-admin.service "$BACKUP/"
[[ -f /etc/apache2/conf-available/webhosting-admin.conf ]] && cp -a /etc/apache2/conf-available/webhosting-admin.conf "$BACKUP/"
printf '%s\n' "$OLD_COMMIT" > "$BACKUP/commit-before.txt"

echo "[2/7] Nieuwe commit activeren"
git -C "$REPO" reset --hard "origin/$BRANCH"

echo "[3/7] Broncode controleren"
cd "$REPO"
npm install --ignore-scripts --package-lock-only >/dev/null
npm run check
bash -n scripts/update-server.sh scripts/install-updater.sh

echo "[4/7] Applicatie installeren"
install -d -m 0755 "$APP/public" "$APP/lib"
cp package.json "$APP/"
[[ -f package-lock.json ]] && cp package-lock.json "$APP/"
cp server.js "$APP/"
cp lib/workspace.js "$APP/lib/"
cp public/* "$APP/public/"
cd "$APP"
if [[ -f package-lock.json ]]; then npm ci --omit=dev; else npm install --omit=dev; fi
chown -R root:root "$APP"

echo "[5/7] Database + configuratie"
mysql -uroot < "$REPO/sql/upgrade.sql"
cp "$REPO/webhosting-admin.service" /etc/systemd/system/webhosting-admin.service
cp "$REPO/apache-admin.conf" /etc/apache2/conf-available/webhosting-admin.conf
apache2ctl configtest
systemctl daemon-reload

echo "[6/7] Herstart + healthcheck"
systemctl restart "$SERVICE"
systemctl reload apache2
sleep 2
systemctl is-active --quiet "$SERVICE"
curl -fsS http://127.0.0.1:3200/health >/dev/null
curl -fsS http://127.0.0.1/admin >/dev/null

echo "[7/7] Deploy geslaagd: $OLD_COMMIT -> $NEW_COMMIT"
mapfile -t OLD < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | tail -n +11 | cut -d' ' -f2-)
((${#OLD[@]} == 0)) || rm -rf -- "${OLD[@]}"
trap - ERR
