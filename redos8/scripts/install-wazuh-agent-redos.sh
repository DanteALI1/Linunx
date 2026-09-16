#!/bin/bash
# install-wazuh-agent-redos.sh — ТОЛЬКО svcsecadmin/root
# Устанавливает wazuh-agent из /opt/install/approved, включает unit, базовая проверка.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -eq 0 || "$(id -un)" == "svcsecadmin" ]] || die "svcsecadmin/root only"

MANAGER_ADDRESS="${1:-}"
APPROVED_DIR="/opt/install/approved"
[[ -n "$MANAGER_ADDRESS" ]] || die "usage: $0 <manager-ip-or-dns> [rpm-path]"

RPM_PATH="${2:-}"
if [[ -z "$RPM_PATH" ]]; then
  RPM_PATH="$(ls -1 "$APPROVED_DIR"/wazuh-agent-*.rpm 2>/dev/null | sort | tail -n1 || true)"
fi
[[ -n "$RPM_PATH" && -f "$RPM_PATH" ]] || die "wazuh-agent rpm not found in $APPROVED_DIR"

echo "[*] Installing dependencies + package: $RPM_PATH"
# РЕД ОС 8: dnf
dnf -y install "$RPM_PATH"

CONF="/var/ossec/etc/ossec.conf"
[[ -f "$CONF" ]] || die "missing $CONF after install"

echo "[*] Setting manager address: $MANAGER_ADDRESS"
# Первичная запись адреса — привилегия svcsecadmin (не editor).
# Дальнейшие правки — editor через sudoedit.
if grep -q '<address>' "$CONF"; then
  sed -i "s#<address>.*</address>#<address>$MANAGER_ADDRESS</address>#" "$CONF"
else
  die "ossec.conf has no <address> placeholder; edit manually as svcsecadmin"
fi

echo "[*] SELinux restorecon..."
restorecon -Rv /var/ossec 2>/dev/null || true

echo "[*] Enable and start wazuh-agent"
systemctl enable --now wazuh-agent
systemctl --no-pager status wazuh-agent || true

echo "[*] Basic log check"
sleep 2
tail -n 30 /var/ossec/logs/ossec.log 2>/dev/null || true

logger -t wazuh-install "installed rpm=$RPM_PATH manager=$MANAGER_ADDRESS"
echo "[+] Done. Editor may sudoedit $CONF; optional: systemctl restart wazuh-agent (narrow alias)."
