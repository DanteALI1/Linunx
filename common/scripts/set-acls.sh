#!/bin/bash
# set-acls.sh — повторное применение ACL после bootstrap

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || exit 1

setfacl -b /opt/install/staging 2>/dev/null || true
chmod 1770 /opt/install/staging
setfacl -m u:svcsec:rwx,g:svcsec:rwx,g:svcsecadmin:rwx,o::--- /opt/install/staging
setfacl -d -m u:svcsec:rwx,g:svcsec:rwx,g:svcsecadmin:rwx,o::--- /opt/install/staging

chmod 0750 /opt/install/approved
chown root:root /opt/install/approved
setfacl -m g:poinstall:rx,g:svcsecadmin:rwx,o::--- /opt/install/approved

# /var/ossec/etc — запись ТОЛЬКО через sudoedit (DAC: root, не давать editor прямой write)
if [[ -d /var/ossec/etc ]]; then
  chown -R root:wazuh /var/ossec/etc 2>/dev/null || chown -R root:root /var/ossec/etc
  find /var/ossec/etc -type f -exec chmod 0640 {} \;
  find /var/ossec/etc -type d -exec chmod 0750 {} \;
  # editor НЕ получает DAC write — только sudoedit (root temp copy)
fi

echo "[+] ACLs applied"
