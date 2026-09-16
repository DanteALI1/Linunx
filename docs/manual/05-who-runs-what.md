# Из-под какой УЗ выполнять работы

Во всех руководствах (`02`/`03`/`04`) команды нужно запускать **строго из-под указанной УЗ**.
Ниже — сводная матрица. Если УЗ ещё не создана — этап выполняет временный bootstrap-админ
(первый root на консоли), затем права передаются `svcsecadmin`.

---

## Учётные записи (УЗ)

| УЗ | UID/тип | SSH | Назначение |
|----|---------|-----|------------|
| **root** (консоль) | 0 | обычно запрещён | Только bootstrap/авария; после внедрения — минимум |
| **svcsecadmin** | системная, в `wheel`/`sudo` | **запрещён** | Полный админ ОС после bootstrap |
| **svcsec** | системная | только SFTP | Поставка артефактов + вызов `super` |
| **poinstaller** (пример) | группа `poinstall` | по политике | Self-contained в `/opt/apps` |
| **editor1** (пример) | группа `editor` | по политике | sudoedit conf |
| *(временная)* член `timeditor` | +группа `timeditor` | как editor | NOPASSWD sudoedit на 8ч |
| **wazuh** | служебная пакета | нет | Только процессы агента (не человек) |

> Имена `poinstaller` / `editor1` — примеры. В проде замените на реальные УЗ,
> сохранив членство в группах `poinstall` / `editor`.

---

## Матрица: этап → УЗ

### A. Базовая настройка сервера (РЕД ОС / Astra)

| Этап | Что делаем | УЗ | Как войти |
|------|------------|----|-----------|
| 0. Пакеты, chrony, hostname | `dnf`/`apt`, timedatectl | **root** (консоль) или первый админ | Локальная консоль / IPMI |
| 1. SELinux enforcing / проверка PARSEC | setenforce, modeswitch | **root** / позже **svcsecadmin** | Консоль |
| 2. Создание групп и УЗ | groupadd, useradd, passwd, ssh keys | **root** | Консоль |
| 3. Каталоги, ACL, fstab noexec | install, setfacl, fstab | **root** → далее **svcsecadmin** | Консоль |
| 4. Установка бинарей `/usr/local/sbin` | install скриптов | **root** / **svcsecadmin** | Консоль |
| 5. sudoers drop-in + `visudo -cf` | копирование файлов | **root** / **svcsecadmin** | Консоль (держать сессию!) |
| 6. sshd drop-in, reload | DenyUsers, Match User | **root** / **svcsecadmin** | Консоль |
| 7. auditd rules + audisp-parsec | rules.d, augenrules | **root** / **svcsecadmin** | Консоль |
| 8. systemd timer timeditor | unit/timer enable | **root** / **svcsecadmin** | Консоль |
| 9. MAC labels / restorecon | semanage, pdpl-* | **svcsecadmin** | Консоль или `super` |
| 10. Приёмка базы | тесты sudo -l, ssh | **svcsecadmin** (+ тесты от ролевых УЗ) | См. ниже |

После этапа 2 целевой оператор админ-работ — **только svcsecadmin**
(root — аварийный запас).

### B. Цепочка поставки и Wazuh

| Шаг | УЗ | Команда / действие | Запрещено другим |
|-----|----|--------------------|--------------------|
| SFTP upload rpm/deb+sha256 | **svcsec** | `sftp` → `/staging` | poinstall, editor |
| Переход к админу | **svcsec** → **svcsecadmin** | `sudo -u svcsecadmin /usr/local/sbin/svcsec-super` | — |
| approve-artifact | **svcsecadmin** | `/usr/local/sbin/approve-artifact ...` | svcsec сам не approve |
| `dnf`/`apt` install wazuh | **svcsecadmin** | install-скрипт или пакетный менеджер | **poinstall — DENY** |
| restorecon / метки PARSEC | **svcsecadmin** | MAC | poinstall, editor |
| `systemctl enable --now wazuh-agent` | **svcsecadmin** | systemd | poinstall; editor — только узкий restart |
| Helpers в `/opt/apps/wazuh-helpers` | **poinstaller** (sudo whitelist) | approved install script | не трогает `/var/ossec` |
| Правка `ossec.conf` | **editor1** или **timeditor** | `sudoedit ...` | не bash, не vim через sudo |
| `systemctl restart wazuh-agent` | **editor1** / **timeditor** (если Cmnd_Alias выдан) или **svcsecadmin** | узкий alias | общий systemctl — DENY |
| Выдача/продление timeditor | **svcsecadmin** | `timeditor-grant` | editor сам не продлевает |
| Снятие timeditor по TTL | **root** via systemd (`timeditor-expire`) | timer | — |
| Разбор ausearch / SIEM | **svcsecadmin** или отдельный SOC-УЗ (read-only) | ausearch | — |
| Rollback RBAC/Wazuh | **svcsecadmin** / **root** консоль | см. `rollback/` | — |

### C. Кто запускает проверки (тесты)

| Тест | Выполняет | Из-под какой УЗ проверяемый эффект |
|------|-----------|-------------------------------------|
| `visudo -cf`, `sshd -t`, `getenforce` | svcsecadmin | — |
| SFTP upload | оператор с ключом svcsec | **svcsec** |
| `sudo -l` / DENY dnf | svcsecadmin запускает `su - poinstaller` | **poinstaller** |
| `sudoedit` / DENY bash | `su - editor1` | **editor1** |
| `matrix-tests.sh` | **root** или **svcsecadmin** | скрипт сам делает `su` на роли |
| `ausearch -k ...` | **svcsecadmin** | — |

---

## Как переключаться между УЗ (практика)

```bash
# Вы уже root/svcsecadmin на консоли — админ-работы:
whoami   # должно быть root или svcsecadmin

# Проверка от имени роли (не «пересесть» навсегда):
su - poinstaller -c 'sudo -n dnf --version'
su - editor1 -c 'sudo -l'

# Переход svcsec → svcsecadmin (на консоли, если svcsec локально допущен):
sudo -u svcsecadmin /usr/local/sbin/svcsec-super

# SSH:
sftp svcsec@server          # OK
ssh svcsecadmin@server      # должно быть DENY
```

**Не делайте** админ-настройку из-под `poinstaller`/`editor1`/`svcsec`.
**Не открывайте** SSH для `svcsecadmin`.

---

## Краткая шпаргалка «кто пишет куда»

| Путь / объект | Пишет УЗ |
|---------------|----------|
| `/opt/install/staging` | **svcsec** (SFTP), читает/чистит **svcsecadmin** |
| `/opt/install/approved` | только **svcsecadmin** |
| `/opt/apps`, `/var/opt/apps` | **poinstaller** (+ svcsecadmin) |
| `/etc/opt/apps/...` | **editor*** через sudoedit |
| `/var/ossec` (пакет, bin, unit) | только **svcsecadmin** (rpm/deb) |
| `/var/ossec/etc/ossec.conf` | **editor*** через sudoedit; первичная установка — **svcsecadmin** |
| `/etc/sudoers*`, `/etc/ssh/*`, audit, MAC, firewall | только **svcsecadmin**/root |
| `/var/lib/rbac-timers` | только **root**/svcsecadmin (grant) и timer |

\* `editor1` или УЗ в группе `timeditor`.
