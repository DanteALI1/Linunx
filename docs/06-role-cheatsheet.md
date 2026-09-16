# Краткая шпаргалка ролей (карточка оператора)

## svcsec
- SFTP → `/opt/install/staging` only
- `super` → svcsecadmin session
- НЕ: dnf/apt, systemctl, /var/ossec

## svcsecadmin
- approve, пакеты ОС, systemd, MAC, firewall, users, sudoers, audit
- SSH: DENY
- Ставит и запускает Wazuh

## poinstall
- `/opt/apps`, `/var/opt/apps` (data noexec)
- helpers: `/opt/apps/wazuh-helpers`
- НЕ: dnf/apt/rpm/dpkg, systemctl, /var/ossec, /etc/systemd

## editor
- sudoedit whitelist (ossec.conf, /etc/opt/apps/...)
- узкий `systemctl restart|status wazuh-agent`
- НЕ: bash/vim через sudo, visudo, shadow, общий systemctl

## timeditor
- как editor + NOPASSWD
- TTL 8ч → `timeditor_expire`
