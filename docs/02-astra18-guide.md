# Пошаговая инструкция: Astra Linux Special Edition 1.8

> **Подробная ручная настройка с пояснениями:**  
> [`manual/03-astra18-manual.md`](manual/03-astra18-manual.md)  
> (теория слоёв: [`manual/01-how-it-works.md`](manual/01-how-it-works.md))

Краткий путь через скрипты — ниже.  
PARSEC (МРД/МКЦ), audisp-parsec, auditd, sudo.

> Имена утилит меток и режимов MAC сверяйте с руководством администратора
> вашей сборки SE 1.8 — в репозитории даны операционные шаблоны.

## 0. Предпосылки

- Astra SE 1.8 с включённым контуром СЗИ (PARSEC).
- Пакеты: `auditd`, `sudo`, `openssh-server`, плагин `audisp-parsec` (имя пакета по документации).
- Артефакты: `wazuh-agent-*.deb` + `.sha256`.

## 1. Развёртывание

```bash
cd /path/to/this/repo
chmod +x common/scripts/*.sh astra18/scripts/*.sh
./astra18/scripts/apply-astra.sh
```

Проверки:

```bash
visudo -cf /etc/sudoers
sshd -t
systemctl is-active auditd
# audisp-parsec
grep active /etc/audisp/plugins.d/audisp-parsec.conf
systemctl list-timers | grep timeditor
```

## 2. PARSEC (МРД/МКЦ)

Следуйте [`../astra18/parsec/CHECKLIST.md`](../astra18/parsec/CHECKLIST.md).

Обязательно:

1. Включить/подтвердить MAC+MIC по профилю СЗИ.
2. Назначить уровни УЗ `svcsec`, `poinstaller`, `editor1`, `svcsecadmin`.
3. После `apt/dpkg` установки Wazuh — проверить/восстановить метки `/var/ossec`.
4. Убедиться, что poinstall/editor **не** читают `/etc/shadow`, `/etc/sudoers`, ключи по мандату.

## 3. Mount-опции

Аналогично РЕД ОС: `noexec` на `/var/opt/apps` и (желательно) staging.
**Не** ставить `noexec` на `/` и системные разделы, включая префикс Wazuh.

## 4. SSH / SFTP

Тот же drop-in [`../common/sshd/50-rbac-roles.conf`](../common/sshd/50-rbac-roles.conf):

- `DenyUsers svcsecadmin`
- `Match User svcsec` → `internal-sftp`, `ChrootDirectory /opt/install`

## 5. Цепочка Wazuh

```text
svcsec: SFTP deb+sha256 → staging
svcsec: super → svcsecadmin
svcsecadmin: approve-artifact
svcsecadmin: install-wazuh-agent-astra <MANAGER>
svcsecadmin: метки PARSEC на /var/ossec (по чеклисту)
editor: sudoedit /var/ossec/etc/ossec.conf
editor: sudo systemctl restart wazuh-agent  # узкий alias
```

### svcsecadmin vs poinstall (Wazuh на Astra)

| Операция | Кто | Почему |
|----------|-----|--------|
| `apt/dpkg install wazuh-agent` | **svcsecadmin** | Системный пакет, unit’ы, `/var/ossec` |
| PARSEC labels / firewall | **svcsecadmin** | Мандат и сеть — админ ОС |
| `/opt/apps/wazuh-helpers` | **poinstall** | Вспомогательные скрипты без прав ОС |
| `sudoedit ossec.conf` | **editor** | Whitelist, без root-shell |

## 6. Аудит + audisp-parsec

Правила: [`../astra18/audit/50-rbac-astra.rules`](../astra18/audit/50-rbac-astra.rules).

```bash
ausearch -k pkg_mgr -ts recent
ausearch -k parsec_admin -ts recent
ausearch -k wazuh_conf -ts recent
ausearch -k artifact_approve -ts recent
# Журналы PARSEC denials — по документации Astra (часто /var/log/parsec* или journal)
```

## 7. timeditor

Идентично РЕД ОС: `timeditor-grant` / timer / `key=timeditor_expire`.

## 8. Приёмка

- [ ] MAC/MIC активны; нет блокирующих PARSEC denials для wazuh-agent
- [ ] audisp-parsec `active=yes`
- [ ] Агент enabled+active, `ossec.conf` с `<address>`
- [ ] Тесты pass/deny из [`../tests/`](../tests/)
- [ ] Rollback: [`../rollback/rollback-astra18.md`](../rollback/rollback-astra18.md)

## Отличия от РЕД ОС 8 (сводка)

| Тема | РЕД ОС 8 | Astra SE 1.8 |
|------|----------|--------------|
| MAC | SELinux enforcing | PARSEC МРД/МКЦ |
| Пакеты | dnf/rpm | apt/dpkg |
| AVC/denials | ausearch -m avc | PARSEC logs + audit |
| Плагин audit | — / setroubleshoot | audisp-parsec |
| Опц. exec policy | fapolicyd | политика PARSEC + DAC |
