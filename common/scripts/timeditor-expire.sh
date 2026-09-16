#!/bin/bash
# timeditor-expire.sh — снять просроченные memberships
# Вызывается systemd timer каждые 15 минут. audit key=timeditor_expire

set -euo pipefail

STATE_DIR="/var/lib/rbac-timers"
AUDIT_KEY="timeditor_expire"
NOW="$(date +%s)"

[[ -d "$STATE_DIR" ]] || exit 0

for state in "$STATE_DIR"/*; do
  [[ -f "$state" ]] || continue
  # shellcheck disable=SC1090
  user=""; expire_epoch=0
  # parse key=value
  while IFS='=' read -r k v; do
    case "$k" in
      user) user="$v" ;;
      expire_epoch) expire_epoch="$v" ;;
    esac
  done < "$state"

  [[ -n "$user" && "$expire_epoch" =~ ^[0-9]+$ ]] || continue
  if (( NOW >= expire_epoch )); then
    if id "$user" >/dev/null 2>&1; then
      # снять только группу timeditor, сохранив остальные
      if command -v gpasswd >/dev/null 2>&1; then
        gpasswd -d "$user" timeditor 2>/dev/null || true
      else
        # fallback: пересобрать группы без timeditor
        CUR="$(id -nG "$user" | tr ' ' '\n' | grep -v '^timeditor$' | tr '\n' ',' | sed 's/,$//')"
        usermod -G "$CUR" "$user" 2>/dev/null || true
      fi
      logger -t timeditor-expire "removed timeditor from user=$user key=$AUDIT_KEY"
      echo "type=USER msg=audit(${NOW}.0:0): user=$user action=expire key=$AUDIT_KEY" \
        >> /var/log/rbac/timeditor-expire.log 2>/dev/null || true
    fi
    rm -f -- "$state"
  fi
done
