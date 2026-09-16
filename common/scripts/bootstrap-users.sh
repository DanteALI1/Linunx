#!/bin/bash
# bootstrap-users.sh — создание групп и УЗ ролей
# svcsecadmin: shell есть, SSH запрещён через sshd drop-in.
# svcsec: ограниченный shell + ForceCommand sftp в drop-in (или nologin + Match).

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || die "run as root"

GROUPS=(svcsec svcsecadmin poinstall editor timeditor)
for g in "${GROUPS[@]}"; do
  getent group "$g" >/dev/null || groupadd --system "$g"
done

# svcsec — поставка; shell минимальный (rbash или /usr/sbin/nologin + sftp Match)
if ! id svcsec >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/svcsec \
    --shell /bin/bash --gid svcsec --groups svcsec svcsec
fi

# svcsecadmin — полный админ; SSH DenyUsers
if ! id svcsecadmin >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/svcsecadmin \
    --shell /bin/bash --gid svcsecadmin --groups svcsecadmin,wheel svcsecadmin 2>/dev/null \
  || useradd --system --create-home --home-dir /home/svcsecadmin \
    --shell /bin/bash --gid svcsecadmin --groups svcsecadmin,sudo svcsecadmin
fi

# Пример прикладных УЗ (замените на реальные имена)
for u in poinstaller editor1; do
  if ! id "$u" >/dev/null 2>&1; then
    case "$u" in
      poinstaller)
        useradd --create-home --shell /bin/bash -g poinstall -G poinstall "$u"
        ;;
      editor1)
        useradd --create-home --shell /bin/bash -g editor -G editor "$u"
        ;;
    esac
  fi
done

# Ключи SSH для svcsec (каталог)
install -d -o svcsec -g svcsec -m 0700 /home/svcsec/.ssh
touch /home/svcsec/.ssh/authorized_keys
chown svcsec:svcsec /home/svcsec/.ssh/authorized_keys
chmod 0600 /home/svcsec/.ssh/authorized_keys

# Запрет интерактивного логина svcsecadmin по паролю локально не трогаем —
# только SSH deny. Локальная консоль/super — допустимы.

passwd -l svcsecadmin 2>/dev/null || true  # опционально: только через super
# Если passwd -l — снимите, если нужен локальный tty login для svcsecadmin.

echo "[+] Users/groups created."
echo "    Add SSH pubkey to /home/svcsec/.ssh/authorized_keys"
echo "    Set passwords for editor1/poinstaller as required by policy."
