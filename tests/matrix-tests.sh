#!/bin/bash
# matrix-tests.sh — positive/negative проверки ролей
# Запускать на целевой ОС после apply-*.sh и (для Wazuh-тестов) установки агента.
# Usage: ./matrix-tests.sh [--with-wazuh]

set -u
WITH_WAZUH=0
[[ "${1:-}" == "--with-wazuh" ]] && WITH_WAZUH=1

PASS=0
FAIL=0
SKIP=0

ok()   { echo "PASS: $*"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP: $*"; SKIP=$((SKIP+1)); }

run_as() {
  local user="$1"; shift
  su -s /bin/bash "$user" -c "$*" 2>/dev/null
}

echo "=== RBAC matrix tests ==="

# --- SSH / identity ---
if id svcsecadmin >/dev/null 2>&1; then
  ok "user svcsecadmin exists"
else
  bad "user svcsecadmin missing"
fi

# --- sudoers syntax ---
if visudo -cf /etc/sudoers >/dev/null 2>&1; then
  ok "visudo -cf /etc/sudoers"
else
  bad "visudo syntax"
fi

# --- svcsec: super allowed path exists ---
if [[ -x /usr/local/sbin/svcsec-super ]]; then
  ok "svcsec-super installed"
else
  bad "svcsec-super missing"
fi

# --- poinstall negatives ---
if id poinstaller >/dev/null 2>&1; then
  if run_as poinstaller "sudo -n dnf --version" ; then
    bad "poinstall must NOT run dnf"
  else
    ok "poinstall denied dnf"
  fi
  if run_as poinstaller "sudo -n apt-get --version" ; then
    bad "poinstall must NOT run apt-get"
  else
    ok "poinstall denied apt-get (or absent)"
  fi
  if run_as poinstaller "sudo -n systemctl status wazuh-agent" ; then
    bad "poinstall must NOT systemctl"
  else
    ok "poinstall denied systemctl"
  fi
else
  skip "poinstaller user not present"
fi

# --- editor negatives / positives ---
if id editor1 >/dev/null 2>&1; then
  if run_as editor1 "sudo -n bash -c id" ; then
    bad "editor must NOT sudo bash"
  else
    ok "editor denied sudo bash"
  fi
  if run_as editor1 "sudo -n vim /etc/passwd" ; then
    bad "editor must NOT sudo vim"
  else
    ok "editor denied sudo vim"
  fi
  if [[ "$WITH_WAZUH" -eq 1 && -f /var/ossec/etc/ossec.conf ]]; then
    # sudoedit non-interactive check: list allowed
    if run_as editor1 "sudo -l" | grep -q 'ossec.conf' ; then
      ok "editor sudo -l shows ossec.conf"
    else
      bad "editor sudo -l missing ossec.conf"
    fi
    if run_as editor1 "sudo -n systemctl restart sshd" ; then
      bad "editor must NOT restart sshd"
    else
      ok "editor denied restart sshd"
    fi
  else
    skip "wazuh conf tests (--with-wazuh to enable)"
  fi
else
  skip "editor1 user not present"
fi

# --- staging permissions ---
if [[ -d /opt/install/staging ]]; then
  if [[ ! -x /opt/install/staging/no_such_exec ]]; then
    ok "staging layout exists"
  fi
  touch /opt/install/staging/.rbac_write_test 2>/dev/null && rm -f /opt/install/staging/.rbac_write_test && ok "root can write staging" || bad "staging not writable by root"
else
  bad "staging missing"
fi

# --- wazuh running ---
if [[ "$WITH_WAZUH" -eq 1 ]]; then
  if systemctl is-active --quiet wazuh-agent; then
    ok "wazuh-agent active"
  else
    bad "wazuh-agent not active"
  fi
fi

# --- auditd ---
if systemctl is-active --quiet auditd 2>/dev/null || service auditd status >/dev/null 2>&1; then
  ok "auditd active"
else
  bad "auditd not active"
fi

echo "=== Summary: PASS=$PASS FAIL=$FAIL SKIP=$SKIP ==="
[[ "$FAIL" -eq 0 ]]
