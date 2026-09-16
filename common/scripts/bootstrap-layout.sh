#!/bin/bash
# bootstrap-layout.sh — создание каталогов, групп, базовых ACL
# Запускать от root на целевой ОС (РЕД ОС или Astra).
# Пользователей создаёт отдельно bootstrap-users.sh

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || die "run as root"

echo "[*] Creating directory layout..."

install -d -o root -g root -m 0755 /opt/install
install -d -o root -g svcsec -m 0770 /opt/install/staging
install -d -o root -g root -m 0750 /opt/install/approved
install -d -o root -g poinstall -m 0770 /opt/apps
install -d -o root -g poinstall -m 0770 /var/opt/apps
install -d -o root -g root -m 0755 /etc/opt/apps
install -d -o root -g root -m 0750 /var/lib/rbac-timers
install -d -o root -g root -m 0750 /usr/local/sbin
install -d -o root -g root -m 0750 /var/log/rbac

# Пример зоны helpers Wazuh (poinstall)
install -d -o root -g poinstall -m 0770 /opt/apps/wazuh-helpers
install -d -o root -g poinstall -m 0770 /var/opt/apps/wazuh-helpers
install -d -o root -g root -m 0750 /etc/opt/apps/wazuh-helpers

# Chroot jail для SFTP svcsec: /opt/install должен быть root:root 755,
# а writable — только staging внутри jail.
# Структура jail:
#   /opt/install          root:root 755  (chroot)
#   /opt/install/staging  root:svcsec 770

echo "[*] Applying ACLs..."
# staging: svcsec пишет, svcsecadmin читает/управляет
setfacl -m g:svcsec:rwx /opt/install/staging
setfacl -m g:svcsecadmin:rwx /opt/install/staging
setfacl -d -m g:svcsec:rwx /opt/install/staging
setfacl -d -m g:svcsecadmin:rwx /opt/install/staging
# запрет удаления чужих файлов (sticky-like через ACL default не полный аналог —
# дополнительно ставим sticky bit)
chmod 1770 /opt/install/staging || chmod 0770 /opt/install/staging

# approved: poinstall — read+exec, запись только root/svcsecadmin
setfacl -m g:poinstall:rx /opt/install/approved
setfacl -m g:svcsecadmin:rwx /opt/install/approved
setfacl -m o::--- /opt/install/approved

# /opt/apps: poinstall rwx
setfacl -m g:poinstall:rwx /opt/apps
setfacl -d -m g:poinstall:rwx /opt/apps
setfacl -m g:svcsecadmin:rwx /opt/apps

# /var/opt/apps: данные, предпочтительно noexec на уровне mount
setfacl -m g:poinstall:rwx /var/opt/apps
setfacl -d -m g:poinstall:rwx /var/opt/apps

# Закрыть чтение секретов ОС от прикладных ролей (дополнительно к DAC)
# (сами файлы остаются root-only; это явная фиксация политики)
for secret in /etc/shadow /etc/gshadow /etc/sudoers /root; do
  [[ -e "$secret" ]] || continue
  # не меняем владельца; убеждаемся что others не читают
  chmod o-rwx "$secret" 2>/dev/null || true
done

echo "[+] Layout ready."
echo "    NOTE: смонтируйте /var/opt/apps с noexec (см. fstab snippets)."
echo "    NOTE: /opt/install/staging — noexec в fstab при отдельном mount."
