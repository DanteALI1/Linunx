#!/bin/bash
# apply-astra.sh — применение RBAC-конфигов на Astra Linux SE 1.8 (root)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ "$(id -u)" -eq 0 ]] || { echo "root required"; exit 1; }

"$ROOT/common/scripts/bootstrap-users.sh"
"$ROOT/common/scripts/bootstrap-layout.sh"
"$ROOT/common/scripts/install-common-bins.sh"
"$ROOT/common/scripts/set-acls.sh"

install -o root -g root -m 0440 "$ROOT/common/sudoers.d/00-rbac-common" /etc/sudoers.d/00-rbac-common
install -o root -g root -m 0440 "$ROOT/astra18/sudoers.d/10-rbac-poinstall-astra" /etc/sudoers.d/10-rbac-poinstall-astra
install -o root -g root -m 0440 "$ROOT/astra18/sudoers.d/20-rbac-editor-wazuh-astra" /etc/sudoers.d/20-rbac-editor-wazuh-astra
visudo -cf /etc/sudoers
visudo -cf /etc/sudoers.d/00-rbac-common
visudo -cf /etc/sudoers.d/10-rbac-poinstall-astra
visudo -cf /etc/sudoers.d/20-rbac-editor-wazuh-astra

install -o root -g root -m 0640 "$ROOT/common/audit/00-base.rules" /etc/audit/rules.d/00-base.rules
install -o root -g root -m 0640 "$ROOT/common/audit/10-hardening-common.rules" /etc/audit/rules.d/10-hardening-common.rules
install -o root -g root -m 0640 "$ROOT/common/audit/10-hardening-syscalls.rules" /etc/audit/rules.d/10-hardening-syscalls.rules
install -o root -g root -m 0640 "$ROOT/astra18/audit/11-hardening-astra.rules" /etc/audit/rules.d/11-hardening-astra.rules
install -o root -g root -m 0640 "$ROOT/astra18/audit/50-rbac-astra.rules" /etc/audit/rules.d/50-rbac-astra.rules
if [[ -d /etc/audisp/plugins.d ]]; then
  install -o root -g root -m 0644 "$ROOT/astra18/audit/audisp-parsec.conf" /etc/audisp/plugins.d/audisp-parsec.conf
fi
# 99-finalize (-e 2) — только после отладки вручную
augenrules --load 2>/dev/null || systemctl restart auditd || service auditd restart

install -d /etc/ssh/sshd_config.d
install -o root -g root -m 0644 "$ROOT/common/sshd/50-rbac-roles.conf" /etc/ssh/sshd_config.d/50-rbac-roles.conf
sshd -t && systemctl reload sshd || service ssh reload

install -o root -g root -m 0644 "$ROOT/common/systemd/timeditor-expire.service" /etc/systemd/system/timeditor-expire.service
install -o root -g root -m 0644 "$ROOT/common/systemd/timeditor-expire.timer" /etc/systemd/system/timeditor-expire.timer
systemctl daemon-reload
systemctl enable --now timeditor-expire.timer

install -o root -g root -m 0750 "$ROOT/astra18/scripts/install-wazuh-agent-astra.sh" /usr/local/sbin/install-wazuh-agent-astra

echo "[+] Astra SE 1.8 RBAC applied"
echo "    Далее: astra18/parsec/CHECKLIST.md"
