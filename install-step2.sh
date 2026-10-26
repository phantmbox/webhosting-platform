#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "[FOUT] Gebruik sudo ./install-step2.sh"; exit 1; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP=/opt/webhosting-admin
CFG=/etc/webhosting-admin
echo "[1/6] Controle"
command -v node >/dev/null || { echo "Node.js ontbreekt"; exit 1; }
command -v npm >/dev/null || { echo "npm ontbreekt"; exit 1; }
systemctl is-active --quiet mysql || { echo "MySQL draait niet"; exit 1; }
install -d -m 0755 "$APP/public" "$APP/lib" /srv/webhosting/www
install -d -m 0750 -o root -g www-data "$CFG"
echo "[2/6] Applicatie"
cp "$SRC/package.json" "$APP/"
cp "$SRC/server.js" "$APP/"
cp "$SRC/lib/workspace.js" "$APP/lib/"
cp "$SRC/public/"* "$APP/public/"
cd "$APP"; npm install --omit=dev
chown -R root:root "$APP"; chown -R www-data:www-data /srv/webhosting/www
echo "[3/6] Database"
mysql -uroot < "$SRC/sql/upgrade.sql"
if [[ ! -f "$CFG/admin.env" ]]; then
 echo "[FOUT] /etc/webhosting-admin/admin.env ontbreekt. Installeer eerst stap 1."; exit 1
fi
grep -q '^WEB_ROOT=' "$CFG/admin.env" || echo 'WEB_ROOT=/srv/webhosting/www' >> "$CFG/admin.env"
grep -q '^OPENAI_MODEL=' "$CFG/admin.env" || echo 'OPENAI_MODEL=gpt-5.5' >> "$CFG/admin.env"
if ! grep -q '^OPENAI_API_KEY=' "$CFG/admin.env"; then echo 'OPENAI_API_KEY=' >> "$CFG/admin.env"; fi
chown root:www-data "$CFG/admin.env"; chmod 0640 "$CFG/admin.env"
echo "[4/6] Service + Apache"
cp "$SRC/webhosting-admin.service" /etc/systemd/system/webhosting-admin.service
cp "$SRC/apache-admin.conf" /etc/apache2/conf-available/webhosting-admin.conf
a2enmod proxy proxy_http headers >/dev/null
a2enconf webhosting-admin >/dev/null || true
apache2ctl configtest
systemctl daemon-reload
systemctl enable webhosting-admin >/dev/null
systemctl restart webhosting-admin
systemctl reload apache2
echo "[5/6] Tests"
sleep 2
systemctl is-active --quiet webhosting-admin
curl -fsS http://127.0.0.1:3200/health >/dev/null
curl -fsS http://127.0.0.1/admin >/dev/null
echo "[6/6] Gereed"
IP="$(hostname -I | awk '{print $1}')"
echo "Admin: http://${IP}/admin"
if grep -q '^OPENAI_API_KEY=$' "$CFG/admin.env"; then
 echo "LET OP: voeg je OpenAI API-key toe aan $CFG/admin.env en restart daarna webhosting-admin."
fi
