# Rollback — Astra Linux SE 1.8

Только svcsecadmin/root с консоли. Учитывайте метки PARSEC при удалении/восстановлении файлов.

## Быстрый откат RBAC-конфигов

```bash
rm -f /etc/sudoers.d/00-rbac-common \
      /etc/sudoers.d/10-rbac-poinstall-astra \
      /etc/sudoers.d/20-rbac-editor-wazuh-astra
visudo -cf /etc/sudoers

rm -f /etc/ssh/sshd_config.d/50-rbac-roles.conf
sshd -t && systemctl reload sshd || service ssh reload

rm -f /etc/audit/rules.d/50-rbac-astra.rules
# audisp-parsec.conf — восстанавливайте из пакета, если меняли:
# apt-get install --reinstall <пакет-audisp-parsec>
augenrules --load || systemctl restart auditd

systemctl disable --now timeditor-expire.timer
rm -f /etc/systemd/system/timeditor-expire.service \
      /etc/systemd/system/timeditor-expire.timer
systemctl daemon-reload

rm -f /usr/local/sbin/svcsec-super \
      /usr/local/sbin/svcsecadmin-session \
      /usr/local/sbin/approve-artifact \
      /usr/local/sbin/timeditor-grant \
      /usr/local/sbin/timeditor-expire \
      /usr/local/sbin/install-wazuh-agent-astra
```

## Откат Wazuh Agent

```bash
systemctl disable --now wazuh-agent
apt-get remove -y wazuh-agent
# apt-get purge -y wazuh-agent   # если нужно удалить conf
```

## PARSEC

После отката конфигов проверьте, что метки критичных путей соответствуют политике орг- consola.
Не отключайте MAC «для удобства» — используйте регламент аварийного доступа Astra SE.

## Аварийный доступ

Rescue/single-user по документации Astra; не удаляйте последнего пользователя с правом смены меток/админ-уровня.
