#!/usr/bin/env bash
# validate-artifacts.sh — статическая проверка комплекта (без целевой ОС)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERR=0

need() { [[ -e "$1" ]] || { echo "MISSING: $1"; ERR=1; }; }

echo "[*] Checking required files..."
need "$ROOT/README.md"
need "$ROOT/docs/00-architecture.md"
need "$ROOT/docs/01-redos8-guide.md"
need "$ROOT/docs/02-astra18-guide.md"
need "$ROOT/docs/03-wazuh-e2e.md"
need "$ROOT/docs/04-bypasses-and-controls.md"
need "$ROOT/common/sudoers.d/00-rbac-common"
need "$ROOT/redos8/sudoers.d/10-rbac-poinstall-redos"
need "$ROOT/redos8/sudoers.d/20-rbac-editor-wazuh-redos"
need "$ROOT/docs/manual/05-who-runs-what.md"
need "$ROOT/docs/manual/06-auditd-rules-catalog.md"
need "$ROOT/common/audit/00-base.rules"
need "$ROOT/common/audit/10-hardening-common.rules"
need "$ROOT/common/audit/10-hardening-syscalls.rules"
need "$ROOT/redos8/audit/11-hardening-redos.rules"
need "$ROOT/redos8/audit/50-rbac-redos.rules"
need "$ROOT/astra18/audit/11-hardening-astra.rules"
need "$ROOT/astra18/sudoers.d/10-rbac-poinstall-astra"
need "$ROOT/astra18/sudoers.d/20-rbac-editor-wazuh-astra"
need "$ROOT/astra18/audit/50-rbac-astra.rules"
need "$ROOT/astra18/audit/audisp-parsec.conf"
need "$ROOT/common/scripts/svcsec-super"
need "$ROOT/common/scripts/approve-artifact"
need "$ROOT/common/systemd/timeditor-expire.timer"
need "$ROOT/tests/matrix-tests.sh"
need "$ROOT/playbooks/wazuh-agent-runbook.md"
need "$ROOT/rollback/rollback-redos8.md"
need "$ROOT/rollback/rollback-astra18.md"

echo "[*] Checking shebangs / executable bits recommendation..."
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if head -n1 "$f" | grep -q '^#!'; then
    if [[ ! -x "$f" ]]; then
      echo "NOTE: not executable yet: $f (chmod +x on apply)"
    fi
  fi
done < <(find "$ROOT/common/scripts" "$ROOT/redos8/scripts" "$ROOT/astra18/scripts" "$ROOT/tests" "$ROOT/playbooks" -type f 2>/dev/null)

# Basic sudoers sanity: no "sudo vim" recommendations in docs
if grep -RIn --exclude-dir=.git 'sudo vim\|sudo nano' "$ROOT/docs" "$ROOT"/*.md 2>/dev/null | grep -v DENY | grep -v 'не ' | grep -v 'НЕ ' | grep -v 'запрет' | grep -v 'Запрет'; then
  echo "WARNING: possible sudo vim/nano suggestion found"
fi

# Forbid global noexec on /
if grep -RIn --exclude-dir=.git 'noexec.*\s/\s' "$ROOT/docs" 2>/dev/null | grep -i recommend; then
  echo "WARNING: possible global noexec on /"
fi

if [[ "$ERR" -ne 0 ]]; then
  echo "FAILED validation"
  exit 1
fi
echo "[+] Validation OK"
