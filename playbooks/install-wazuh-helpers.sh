#!/bin/bash
# Пример скрипта для /opt/install/approved/install-wazuh-helpers.sh
# Выполняется poinstall через sudo EXEC whitelist.
# НЕ устанавливает wazuh-agent в ОС.

set -euo pipefail

APP=wazuh-helpers
SRC_ROOT="/opt/install/approved/${APP}"
DST="/opt/apps/${APP}"
DATA="/var/opt/apps/${APP}"

die() { echo "ERROR: $*" >&2; exit 1; }

# Защита от вызова package managers (defense in depth)
for bad in dnf yum rpm apt apt-get dpkg systemctl; do
  if [[ "${1:-}" == "$bad" ]]; then
    die "refusing to run package/service manager"
  fi
done

[[ "$(id -u)" -eq 0 ]] || die "must run via sudo as root"

mkdir -p "$DST/bin" "$DST/lib" "$DATA" "/etc/opt/apps/${APP}"

if [[ -d "$SRC_ROOT" ]]; then
  cp -a "$SRC_ROOT/." "$DST/"
else
  # минимальный helper-заглушка
  cat > "$DST/bin/collect-ossec-tail.sh" <<'EOF'
#!/bin/bash
# Read-only helper: tail agent log if permitted by DAC
exec /usr/bin/tail -n "${1:-100}" /var/ossec/logs/ossec.log
EOF
  chmod 0755 "$DST/bin/collect-ossec-tail.sh"
fi

chown -R root:poinstall "$DST"
chmod -R g+rX,o= "$DST"
chown -R root:poinstall "$DATA"

logger -t wazuh-helpers "installed to $DST"
echo "[+] wazuh-helpers installed under $DST (no OS package changes)"
