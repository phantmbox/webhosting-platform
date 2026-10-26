#!/usr/bin/env bash
set -Eeuo pipefail

REPO="/opt/webhosting-platform"
APP="/opt/webhosting-admin"
BACKUP_ROOT="/srv/webhosting/backups/platform"
SERVICE="webhosting-admin"
BRANCH="${BRANCH:-main}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$STAMP"
OLD_COMMIT=""

[[ $EUID -eq 0 ]] || { echo "[FOUT] Gebruik: sudo $0"; exit 1; }
[[ -d "$REPO/.git" ]] || { echo "[FOUT] Git repository ontbreekt: $REPO"; exit 1; }
command -v node >/dev/null
command -v npm >/dev/null
command -v git >/dev/null
command -v curl >/dev/null

mkdir -p "$BACKUP_ROOT"
OLD_COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"

rollback() {
  rc=$?
  trap - ERR
  echo "[ROLLBACK] Update mislukt; vorige applicatie wordt teruggezet."
  if [[ -d "$BACKUP/app" ]]; then
    rm -rf "$APP"
    cp -a "$BACKUP/app" "$APP"
  fi
  [[ -f "$BACKUP/webhosting-admin.service" ]] && cp -a "$BACKUP/webhosting-admin.service" /etc/systemd/system/webhosting-admin.service
  [[ -f "$BACKUP/webhosting-admin.conf" ]] && cp -a "$BACKUP/webhosting-admin.conf" /etc/apache2/conf-available/webhosting-admin.conf
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

echo "[2/7] GitHub ophalen"
git -C "$REPO" fetch origin "$BRANCH"
git -C "$REPO" checkout -B "$BRANCH" "origin/$BRANCH"

echo "[3/7] Broncode controleren"
cd "$REPO"
npm install --ignore-scripts --package-lock-only >/dev/null
npm run check

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

echo "[5/7] Configuratie + database"
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

echo "[7/7] Klaar"
NEW_COMMIT="$(git -C "$REPO" rev-parse HEAD)"
echo "Van: ${OLD_COMMIT:-geen eerdere commit}"
echo "Naar: $NEW_COMMIT"
echo "Backup: $BACKUP"

# Bewaar maximaal 10 platformbackups.
mapfile -t OLD < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | tail -n +11 | cut -d' ' -f2-)
((${#OLD[@]} == 0)) || rm -rf -- "${OLD[@]}"
trap - ERR
