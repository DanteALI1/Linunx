# Rollback — РЕД ОС 8

Выполняет **только svcsecadmin/root** с консоли.

## Быстрый откат RBAC-конфигов (сохранить Wazuh)

```bash
# 1. Убрать sudoers drop-ins
rm -f /etc/sudoers.d/00-rbac-common \
      /etc/sudoers.d/10-rbac-poinstall-redos \
      /etc/sudoers.d/20-rbac-editor-wazuh-redos
visudo -cf /etc/sudoers

# 2. SSH drop-in
rm -f /etc/ssh/sshd_config.d/50-rbac-roles.conf
sshd -t && systemctl reload sshd

# 3. Audit rules
rm -f /etc/audit/rules.d/50-rbac-redos.rules
augenrules --load || systemctl restart auditd

# 4. Timer
systemctl disable --now timeditor-expire.timer
rm -f /etc/systemd/system/timeditor-expire.service \
      /etc/systemd/system/timeditor-expire.timer
systemctl daemon-reload

# 5. Binaries (опционально)
rm -f /usr/local/sbin/svcsec-super \
      /usr/local/sbin/svcsecadmin-session \
      /usr/local/sbin/approve-artifact \
      /usr/local/sbin/timeditor-grant \
      /usr/local/sbin/timeditor-expire \
      /usr/local/sbin/install-wazuh-agent-redos
```

## Откат Wazuh Agent

```bash
systemctl disable --now wazuh-agent
dnf remove -y wazuh-agent
# данные/логи при необходимости:
# rm -rf /var/ossec
```

## Откат пользователей/групп (осторожно)

```bash
# только если УЗ создавались этим комплектом и не используются иначе
userdel svcsec 2>/dev/null || true
# svcsecadmin — не удаляйте, пока нет альтернативного админ-доступа!
groupdel timeditor 2>/dev/null || true
```

## Аварийный доступ

Если sudoers сломан: загрузитесь в rescue, `mount -o remount,rw /`, исправьте `/etc/sudoers.d`, `visudo -cf`.
SELinux: `setenforce 0` только для аварийного ремонта, затем вернуть enforcing.
