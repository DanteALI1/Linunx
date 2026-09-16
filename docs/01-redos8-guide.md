# Пошаговая инструкция: РЕД ОС 8

SELinux **enforcing**, auditd, sudo, ориентиры ФСТЭК — см. также [`05-fstek-notes.md`](05-fstek-notes.md).

## 0. Предпосылки

- РЕД ОС 8, root на консоли или через существующий админ-доступ.
- Пакеты: `audit`, `policycoreutils-python-utils` (или аналоги), `sudo`, `openssh-server`, `setools-console`.
- Опционально: `fapolicyd`, `setroubleshoot`.
- Артефакты Wazuh: `wazuh-agent-*.rpm` + `.sha256`.

## 1. Развёртывание ролей и каталогов

```bash
cd /path/to/this/repo
chmod +x common/scripts/*.sh redos8/scripts/*.sh
./redos8/scripts/apply-redos.sh
```

Скрипт создаёт группы/УЗ, каталоги, ACL, sudoers, audit rules, sshd drop-in, timer timeditor.

Проверки:

```bash
getenforce                    # Enforcing
visudo -cf /etc/sudoers
sshd -t
systemctl is-active auditd
systemctl list-timers | grep timeditor
```

## 2. SELinux

Следуйте [`../redos8/selinux/CHECKLIST.md`](../redos8/selinux/CHECKLIST.md).

```bash
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
restorecon -Rv /opt/install /opt/apps /var/opt/apps
```

После установки Wazuh: `restorecon -Rv /var/ossec`.

## 3. Mount-опции (exec policy)

См. [`../common/acl/fstab.snippets`](../common/acl/fstab.snippets).

- `/var/opt/apps` — `noexec,nodev,nosuid`
- `/opt/install/staging` (если отдельный FS) — `noexec`
- **Не** ставить `noexec` на `/`, `/usr`, `/var/ossec`

## 4. SSH / SFTP svcsec

1. Добавьте pubkey в `/home/svcsec/.ssh/authorized_keys`.
2. Убедитесь, что `/opt/install` — `root:root 755` (требование ChrootDirectory).
3. `systemctl reload sshd`.
4. Тест: `sftp svcsec@host` → только `/staging`, без shell.

## 5. Цепочка Wazuh (кратко)

Полный сценарий: [`03-wazuh-e2e.md`](03-wazuh-e2e.md).

```text
svcsec: SFTP → /opt/install/staging/wazuh-agent-*.rpm(+sha256)
svcsec: super  →  (sudo -u svcsecadmin svcsec-super)
svcsecadmin: approve-artifact ...
svcsecadmin: install-wazuh-agent-redos <MANAGER>
editor: sudoedit /var/ossec/etc/ossec.conf
editor: sudo systemctl restart wazuh-agent   # узкий Cmnd_Alias
```

### Разделение svcsecadmin vs poinstall/editor (Wazuh)

| Операция | Кто | Почему безопасно |
|----------|-----|------------------|
| `dnf install wazuh-agent-*.rpm` | **svcsecadmin** | Пишет в `/usr`, `/var/ossec`, unit’ы — зона ОС |
| `systemctl enable --now wazuh-agent` | **svcsecadmin** | Управление службами |
| helpers в `/opt/apps/wazuh-helpers` | **poinstall** | Не трогает rpm/systemd/`/var/ossec` |
| правка `ossec.conf` | **editor** | Только sudoedit whitelist |
| upload rpm | **svcsec** | Только staging, без install |

## 6. Аудит

```bash
ausearch -k pkg_mgr -ts recent
ausearch -k wazuh_conf -ts recent
ausearch -k svcsec_super -ts recent
ausearch -k sudo_exec -ts recent
ausearch -m avc -ts recent
```

Правила: [`../redos8/audit/50-rbac-redos.rules`](../redos8/audit/50-rbac-redos.rules).

## 7. Опционально fapolicyd

Скопируйте [`../redos8/fapolicyd/70-rbac-apps.rules`](../redos8/fapolicyd/70-rbac-apps.rules), обновите trust DB, перезапустите службу. Проверьте, что `/var/ossec/bin` и `/opt/apps` не ломаются.

## 8. timeditor

```bash
# как svcsecadmin
sudo /usr/local/sbin/timeditor-grant editor1
# через ≤8ч timer снимет группу; ключ audit: timeditor_expire
```

## 9. Приёмка

- [ ] SELinux Enforcing, нет критичных AVC для wazuh-agent
- [ ] Агент active, логи без ошибок прав
- [ ] Positive/negative тесты из [`../tests/`](../tests/) пройдены
- [ ] Rollback документён ([`../rollback/`](../rollback/))

## 10. Rollback

См. [`../rollback/rollback-redos8.md`](../rollback/rollback-redos8.md).
