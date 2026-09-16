#!/bin/bash
# timeditor-grant.sh — выдать membership в timeditor на 8 часов
# Только svcsecadmin/root. State: /var/lib/rbac-timers/<user> mode 0600 root:root

set -euo pipefail

STATE_DIR="/var/lib/rbac-timers"
TTL_SECONDS=$((8 * 3600))
AUDIT_KEY="timeditor_grant"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -eq 0 || "$(id -un)" == "svcsecadmin" ]] || die "admin only"

USER_NAME="${1:-}"
[[ -n "$USER_NAME" ]] || die "usage: $0 <username>"
id "$USER_NAME" >/dev/null 2>&1 || die "unknown user: $USER_NAME"
getent group timeditor >/dev/null || die "group timeditor missing"

EXPIRE_AT=$(( $(date +%s) + TTL_SECONDS ))
install -d -o root -g root -m 0750 "$STATE_DIR"
STATE_FILE="${STATE_DIR}/${USER_NAME}"
umask 077
printf 'user=%s\nexpire_epoch=%s\ngranted_by=%s\ngranted_at=%s\n' \
  "$USER_NAME" "$EXPIRE_AT" "$(id -un)" "$(date -Is)" > "$STATE_FILE"
chown root:root "$STATE_FILE"
chmod 0600 "$STATE_FILE"

usermod -a -G timeditor "$USER_NAME"
logger -t timeditor-grant "user=$USER_NAME expire=$EXPIRE_AT key=$AUDIT_KEY"
echo "[+] Granted timeditor to $USER_NAME until $(date -d "@$EXPIRE_AT" -Is 2>/dev/null || date -r "$EXPIRE_AT" -Is)"
