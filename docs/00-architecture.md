# Целевая архитектура RBAC / аудита / изоляции

## Контуры

1. **Поставка артефактов** — `svcsec` (SFTP → staging).
2. **Прикладная установка** — `poinstall` (`/opt/apps`, self-contained).
3. **Ограниченное редактирование conf** — `editor` / `timeditor` (sudoedit whitelist).
4. **Системное администрирование** — `svcsecadmin` (пакеты ОС, systemd, MAC, users, sudoers, audit, сеть).

## Карта каталогов

| Путь | Назначение | Exec | Кто пишет |
|------|------------|------|-----------|
| `/opt/install/staging/` | Приём файлов (SFTP chroot) | нет (noexec) | svcsec (SFTP), svcsecadmin (approve) |
| `/opt/install/approved/` | Артефакты после проверки | да (для poinstall) | только svcsecadmin |
| `/opt/apps/<app>/` | Self-contained приложения | да | poinstall, svcsecadmin |
| `/var/opt/apps/<app>/` | Данные приложений | **NOEXEC** | poinstall (данные), app runtime |
| `/etc/opt/apps/<app>/` | Conf приложений | нет | editor via sudoedit |
| `/var/ossec/` | Штатный префикс Wazuh | да (бинарники пакета) | **только svcsecadmin** (пакеты) |
| `/var/ossec/etc/` | Конфиги Wazuh | нет | editor via sudoedit (whitelist) |
| `/var/ossec/logs/` | Логи Wazuh | нет | wazuh процессы |

> `/var/ossec` **не** является зоной записи poinstall. Установку rpm/deb выполняет svcsecadmin.

## Модель зависимостей

```
[поставщик] --SFTP--> staging --(svcsecadmin approve)--> approved
                                                              |
                    +-----------------------------------------+
                    |                                         |
            self-contained                            системный пакет
                    |                                         |
              poinstall --> /opt/apps/<app>         svcsecadmin --> dnf/apt
                    |                                         |
              /var/opt/apps (data)                    /var/ossec + systemd
                    |                                         |
              editor: /etc/opt/apps                   editor: sudoedit ossec.conf
```

## Матрица ответственности (Wazuh)

| Действие | svcsec | poinstall | editor | timeditor | svcsecadmin |
|----------|:------:|:---------:|:------:|:---------:|:-----------:|
| SFTP upload rpm/deb в staging | ✓ | ✗ | ✗ | ✗ | ✗ |
| Проверка hash + approve | ✗ | ✗ | ✗ | ✗ | ✓ |
| dnf/apt install wazuh-* | ✗ | ✗ | ✗ | ✗ | ✓ |
| systemctl enable/start wazuh-* | ✗ | ✗ | ✗* | ✗* | ✓ |
| sudoedit `/var/ossec/etc/ossec.conf` | ✗ | ✗ | ✓ | ✓ | ✓ |
| helpers в `/opt/apps/wazuh-helpers` | ✗ | ✓ | ✗ | ✗ | ✓ |
| `super` → svcsecadmin | ✓ | ✗ | ✗ | ✗ | — |
| SSH на svcsecadmin | ✗ | ✗ | ✗ | ✗ | ✗ |

\* `restart wazuh-agent` — только при явном узком `Cmnd_Alias`; иначе ✗.

## Кто что делает в примере Wazuh

| Шаг | Роль | Почему безопасно |
|-----|------|------------------|
| Upload пакета в staging | svcsec | Chroot SFTP, без shell/exec/overwrite |
| Hash + перенос в approved + dnf/apt + enable/start | svcsecadmin | Единственный полный админ; SSH закрыт |
| Helpers/offline tools в `/opt/apps/wazuh-helpers` | poinstall | Не трогает пакетный менеджер и `/var/ossec` |
| Правка `ossec.conf` | editor/timeditor | Только sudoedit whitelist; опц. узкий restart |
| Переход svcsec→admin | svcsec via `super` | UX-обёртка над `sudo -u svcsecadmin ...`; не даёт svcsec root |

## Глобальная политика EXEC

- Прикладной exec для poinstall: `/opt/install/approved`, `/opt/apps`.
- `/var/opt/apps` — **без exec** (mount `noexec` или аналог).
- Бинарники Wazuh в `/var/ossec` управляются MAC + systemd от svcsecadmin.
- **Запрещено** ставить `noexec` на `/`, `/usr`, `/bin`, `/sbin`.

## Слои контроля (не aliases)

1. **DAC/ACL** — владельцы, группы, `setfacl`.
2. **sudoers** — whitelist команд, `NOEXEC`, `!SHELLS`, `sudoedit`.
3. **MAC** — SELinux (РЕД ОС) / PARSEC МРД+МКЦ (Astra).
4. **auditd** (+ audisp-parsec на Astra).
5. **sshd/PAM** — allow/deny пользователей, ForceCommand internal-sftp.
6. Опционально **fapolicyd** (РЕД ОС).

Shell aliases и `~/.bashrc` — только UX, **не СЗИ**.
