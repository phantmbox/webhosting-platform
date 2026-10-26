# Webhosting Platform

AI-webhosting beheerplatform. De admin-interface blijft alleen via het lokale netwerk bereikbaar.

## Serverpaden
- Git broncode: `/opt/webhosting-platform`
- Actieve Node-app: `/opt/webhosting-admin`
- Webspaces: `/srv/webhosting/www`
- Config/secrets: `/etc/webhosting-admin/admin.env` (niet in Git)
- Backups updater: `/srv/webhosting/backups/platform`

## Updaten
Na installatie van de updater:

```bash
sudo webhosting-update
```

De updater maakt eerst een backup, haalt `main` op, controleert JavaScript, installeert dependencies, voert de database-upgrade uit, test Apache, herstart de service en voert healthchecks uit. Bij een fout wordt de vorige applicatie teruggezet.
