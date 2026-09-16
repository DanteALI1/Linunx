#!/bin/bash
# apply-redos.sh — применение RBAC-конфигов на РЕД ОС 8 (root)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ "$(id -u)" -eq 0 ]] || { echo "root required"; exit 1; }

"$ROOT/common/scripts/bootstrap-users.sh"
"$ROOT/common/scripts/bootstrap-layout.sh"
"$ROOT/common/scripts/install-common-bins.sh"
"$ROOT/common/scripts/set-acls.sh"

install -o root -g root -m 0440 "$ROOT/common/sudoers.d/00-rbac-common" /etc/sudoers.d/00-rbac-common
install -o root -g root -m 0440 "$ROOT/redos8/sudoers.d/10-rbac-poinstall-redos" /etc/sudoers.d/10-rbac-poinstall-redos
install -o root -g root -m 0440 "$ROOT/redos8/sudoers.d/20-rbac-editor-wazuh-redos" /etc/sudoers.d/20-rbac-editor-wazuh-redos
visudo -cf /etc/sudoers
visudo -cf /etc/sudoers.d/00-rbac-common
visudo -cf /etc/sudoers.d/10-rbac-poinstall-redos
visudo -cf /etc/sudoers.d/20-rbac-editor-wazuh-redos

install -o root -g root -m 0640 "$ROOT/common/audit/00-base.rules" /etc/audit/rules.d/00-base.rules
install -o root -g root -m 0640 "$ROOT/common/audit/10-hardening-common.rules" /etc/audit/rules.d/10-hardening-common.rules
install -o root -g root -m 0640 "$ROOT/common/audit/10-hardening-syscalls.rules" /etc/audit/rules.d/10-hardening-syscalls.rules
install -o root -g root -m 0640 "$ROOT/redos8/audit/11-hardening-redos.rules" /etc/audit/rules.d/11-hardening-redos.rules
install -o root -g root -m 0640 "$ROOT/redos8/audit/50-rbac-redos.rules" /etc/audit/rules.d/50-rbac-redos.rules
# 99-finalize (-e 2) — только после отладки вручную:
# install -m 0640 "$ROOT/common/audit/99-finalize.rules.example" /etc/audit/rules.d/99-finalize.rules
augenrules --load 2>/dev/null || service auditd restart || systemctl restart auditd

install -d /etc/ssh/sshd_config.d
install -o root -g root -m 0644 "$ROOT/common/sshd/50-rbac-roles.conf" /etc/ssh/sshd_config.d/50-rbac-roles.conf
sshd -t && systemctl reload sshd

install -o root -g root -m 0644 "$ROOT/common/systemd/timeditor-expire.service" /etc/systemd/system/timeditor-expire.service
install -o root -g root -m 0644 "$ROOT/common/systemd/timeditor-expire.timer" /etc/systemd/system/timeditor-expire.timer
systemctl daemon-reload
systemctl enable --now timeditor-expire.timer

install -o root -g root -m 0750 "$ROOT/redos8/scripts/install-wazuh-agent-redos.sh" /usr/local/sbin/install-wazuh-agent-redos

# SELinux enforcing check
if command -v getenforce >/dev/null; then
  cur="$(getenforce)"
  echo "[*] SELinux: $cur"
  [[ "$cur" == "Enforcing" ]] || echo "WARNING: set enforcing before acceptance"
fi

echo "[+] РЕД ОС 8 RBAC applied"
