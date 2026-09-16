# RBAC, аудит и изоляция среды

Детальные технические инструкции, скрипты и конфигурации для разграничения ролей
на **РЕД ОС 8** (SELinux) и **Astra Linux Special Edition 1.8** (PARSEC).

Сквозной пример внедрения: **Wazuh Agent** (upload → approve → install/start → config edit → audit).

## Структура

| Путь | Назначение |
|------|------------|
| [`docs/00-architecture.md`](docs/00-architecture.md) | Целевая архитектура, роли, матрица Wazuh |
| [`docs/01-redos8-guide.md`](docs/01-redos8-guide.md) | Пошаговая инструкция РЕД ОС 8 |
| [`docs/02-astra18-guide.md`](docs/02-astra18-guide.md) | Пошаговая инструкция Astra SE 1.8 |
| [`docs/03-wazuh-e2e.md`](docs/03-wazuh-e2e.md) | End-to-end сценарий Wazuh для обеих ОС |
| [`docs/04-bypasses-and-controls.md`](docs/04-bypasses-and-controls.md) | Известные обходы и контрмеры |
| [`docs/05-fstek-notes.md`](docs/05-fstek-notes.md) | Рекомендации ФСТЭК (ориентиры для РЕД ОС) |
| [`docs/06-role-cheatsheet.md`](docs/06-role-cheatsheet.md) | Шпаргалка ролей |
| [`common/`](common/) | Общие скрипты, шаблоны ACL, systemd |
| [`redos8/`](redos8/) | Конфиги и скрипты только для РЕД ОС 8 |
| [`astra18/`](astra18/) | Конфиги и скрипты только для Astra SE 1.8 |
| [`tests/`](tests/) | Positive/negative тесты + ausearch |
| [`playbooks/`](playbooks/) | Runbook установки Wazuh |
| [`rollback/`](rollback/) | Процедуры отката |

## Роли (кратко)

| Роль | Что делает | Чего не делает |
|------|------------|----------------|
| **svcsec** | SFTP в staging; `super` → svcsecadmin | Не ставит пакеты, не systemctl, не пишет в `/var/ossec` |
| **svcsecadmin** | Approve, dnf/apt, systemd, MAC, sudoers, audit, firewall | SSH запрещён |
| **poinstall** | Self-contained ПО в `/opt/apps`; helpers Wazuh | Не dnf/apt/rpm, не systemctl, не `/var/ossec` |
| **editor** | `sudoedit` whitelist (в т.ч. `ossec.conf`) | Нет root-shell, visudo, usermod |
| **timeditor** | Как editor + NOPASSWD, TTL 8ч | То же + авто-снятие группы |

## Ручная настройка (подробно)

Поэтапная настройка сервера **без** «просто запусти скрипт» — с примерами и
объяснением, как работает каждый слой:

→ **[`docs/manual/README.md`](docs/manual/README.md)**

| Документ | Содержание |
|----------|------------|
| [how-it-works](docs/manual/01-how-it-works.md) | Слои СЗИ, роли, sudoers/audit/MAC на пальцах |
| [РЕД ОС 8 вручную](docs/manual/02-redos8-manual.md) | Этапы 0–12: пакеты → SELinux → УЗ → ACL → sudo → SSH → audit → timer |
| [Astra SE 1.8 вручную](docs/manual/03-astra18-manual.md) | То же для PARSEC + audisp-parsec + apt |
| [Wazuh вручную](docs/manual/04-wazuh-manual.md) | Upload → approve → install → sudoedit → negative tests |

Скрипты `apply-*.sh` — автоматизация того же порядка; для обучения и аудита
конфигурации используйте ручной путь.

## Быстрый старт (скрипты)

1. Выберите контур ОС: `docs/01-redos8-guide.md` **или** `docs/02-astra18-guide.md`.
2. Разверните базовые каталоги и роли (`./redos8/scripts/apply-redos.sh` или Astra-аналог).
3. Пройдите [`docs/03-wazuh-e2e.md`](docs/03-wazuh-e2e.md) или ручной [`docs/manual/04-wazuh-manual.md`](docs/manual/04-wazuh-manual.md).
4. Прогоните [`tests/`](tests/) и зафиксируйте ausearch.

## Принципы СЗИ (обязательные)

- Контроль = **DAC/ACL + sudoers + MAC + auditd** (не shell aliases).
- Привилегированное редактирование — **только sudoedit**.
- Запрет shell-escape и интерактивных shell через sudo.
- **Не** ставить `noexec` на `/` и системные разделы.
- Системные пакеты и unit’ы (включая Wazuh) — **только svcsecadmin**.
- Self-contained приложения — зона **poinstall** в `/opt/apps`.

## Контраст установки

| Тип ПО | Кто ставит | Куда | Кто конфигурирует |
|--------|------------|------|-------------------|
| Self-contained | poinstall | `/opt/apps/<app>` | editor → `/etc/opt/apps/<app>` |
| Wazuh (rpm/deb) | **svcsecadmin** | `/var/ossec` + systemd | editor → sudoedit `ossec.conf` |
