#!/bin/bash
# install-common-bins.sh — установить общие бинарники в /usr/local/sbin

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "root required"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install -o root -g root -m 0750 "$SCRIPT_DIR/svcsec-super" /usr/local/sbin/svcsec-super
install -o root -g root -m 0750 "$SCRIPT_DIR/svcsecadmin-session" /usr/local/sbin/svcsecadmin-session
install -o root -g root -m 0750 "$SCRIPT_DIR/approve-artifact" /usr/local/sbin/approve-artifact
install -o root -g root -m 0750 "$SCRIPT_DIR/timeditor-grant.sh" /usr/local/sbin/timeditor-grant
install -o root -g root -m 0750 "$SCRIPT_DIR/timeditor-expire.sh" /usr/local/sbin/timeditor-expire
install -o root -g root -m 0750 "$SCRIPT_DIR/bootstrap-layout.sh" /usr/local/sbin/rbac-bootstrap-layout
install -o root -g root -m 0750 "$SCRIPT_DIR/bootstrap-users.sh" /usr/local/sbin/rbac-bootstrap-users

echo "[+] Installed common binaries to /usr/local/sbin"
