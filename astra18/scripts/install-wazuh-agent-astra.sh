#!/bin/bash
# install-wazuh-agent-astra.sh — ТОЛЬКО svcsecadmin/root
# Установка wazuh-agent из /opt/install/approved на Astra SE 1.8

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -eq 0 || "$(id -un)" == "svcsecadmin" ]] || die "svcsecadmin/root only"

MANAGER_ADDRESS="${1:-}"
APPROVED_DIR="/opt/install/approved"
[[ -n "$MANAGER_ADDRESS" ]] || die "usage: $0 <manager-ip-or-dns> [deb-path]"

DEB_PATH="${2:-}"
if [[ -z "$DEB_PATH" ]]; then
  DEB_PATH="$(ls -1 "$APPROVED_DIR"/wazuh-agent-*.deb 2>/dev/null | sort | tail -n1 || true)"
fi
[[ -n "$DEB_PATH" && -f "$DEB_PATH" ]] || die "wazuh-agent deb not found in $APPROVED_DIR"

echo "[*] Installing package: $DEB_PATH"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y "$DEB_PATH" || dpkg -i "$DEB_PATH"
apt-get -f install -y || true

CONF="/var/ossec/etc/ossec.conf"
[[ -f "$CONF" ]] || die "missing $CONF after install"

echo "[*] Setting manager address: $MANAGER_ADDRESS"
if grep -q '<address>' "$CONF"; then
  sed -i "s#<address>.*</address>#<address>$MANAGER_ADDRESS</address>#" "$CONF"
else
  die "ossec.conf has no <address> placeholder"
fi

echo "[*] PARSEC labels: review/apply per astra18/parsec/CHECKLIST.md"
# Место для вызова утилит меток вашей сборки, например:
# pdpl-file ... /var/ossec

echo "[*] Enable and start wazuh-agent"
systemctl enable --now wazuh-agent
systemctl --no-pager status wazuh-agent || true

sleep 2
tail -n 30 /var/ossec/logs/ossec.log 2>/dev/null || true

logger -t wazuh-install "installed deb=$DEB_PATH manager=$MANAGER_ADDRESS"
echo "[+] Done."
