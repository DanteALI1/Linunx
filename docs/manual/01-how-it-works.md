# Как это работает: слои контроля и роли

Перед ручной настройкой важно понимать модель. Иначе легко «починить» симптом
командой, которая ломает безопасность (например `sudo vim` или `noexec` на `/`).

---

## 1. Цель модели

Нужно разделить людей и процессы так, чтобы:

1. Поставщик артефактов **не мог** поставить пакет в ОС и не видел секреты.
2. Установщик прикладного self-contained ПО **не мог** стать админом ОС.
3. Редактор конфигов **не мог** получить root-shell.
4. Полный админ ОС существовал, но **без SSH** и вызывался контролируемо.
5. Все чувствительные действия попадали в **audit**.

Это достигается **несколькими слоями сразу**. Один слой (например, только группы
Unix или только alias в `.bashrc`) недостаточен.

---

## 2. Слои защиты (снизу вверх по «жёсткости»)

```
┌─────────────────────────────────────────────────────────┐
│ 5. auditd (+ audisp-parsec на Astra)                    │  ← фиксирует факты
├─────────────────────────────────────────────────────────┤
│ 4. MAC: SELinux (РЕД ОС) / PARSEC (Astra)               │  ← мандат, даже если DAC обойден
├─────────────────────────────────────────────────────────┤
│ 3. sudoers (whitelist, sudoedit, NOEXEC)                │  ← что можно сделать от root
├─────────────────────────────────────────────────────────┤
│ 2. DAC + ACL (владельцы, chmod, setfacl)                │  ← кто пишет в каталоги
├─────────────────────────────────────────────────────────┤
│ 1. SSH / PAM (Match User, DenyUsers, ForceCommand)      │  ← кто вообще входит и как
└─────────────────────────────────────────────────────────┘
         ↑
   Shell aliases / .bashrc  — НЕ слой СЗИ (только удобство)
```

### Пример: почему нужен весь стек

Сценарий: пользователь `editor1` хочет править `/var/ossec/etc/ossec.conf`.

| Слой | Что происходит |
|------|----------------|
| SSH | editor1 может зайти по ключу (если политика разрешает) |
| DAC | файл `0640 root:wazuh` — editor1 **не** может писать напрямую |
| sudoers | разрешён **только** `sudoedit /var/ossec/etc/ossec.conf` |
| MAC | процесс sudoedit/служба работают в своих доменах/метках |
| audit | факт правки пишется с key `wazuh_conf` / sudo.log |

Если бы дали `sudo vim /var/ossec/etc/ossec.conf`, из vim через `:!bash`
получился бы root-shell — **обход**. Поэтому vim через sudo запрещён, используется
механизм **sudoedit** (копия во временный файл пользователя, затем атомарная
замена от root).

---

## 3. Роли и учётные записи

### 3.1. Группы (RBAC «логический»)

| Группа | Смысл | Типичный УЗ |
|--------|-------|-------------|
| `svcsec` | поставка файлов | `svcsec` |
| `svcsecadmin` | админ ОС | `svcsecadmin` |
| `poinstall` | установка в `/opt/apps` | `poinstaller` |
| `editor` | правка conf через sudoedit | `editor1` |
| `timeditor` | временный editor без пароля sudo | добавляется на 8 часов |

Группа сама по себе почти ничего не даёт. Права появляются из связки:
**membership → sudoers `%group` → ACL на каталоги → MAC**.

### 3.2. svcsec — «курьер файлов»

**Может:**
- подключиться по SSH **только** как SFTP;
- положить файл в `/opt/install/staging/`;
- вызвать `super` (обёртка над `sudo -u svcsecadmin /usr/local/sbin/svcsec-super`).

**Не может:**
- получить обычный shell на сервере (ForceCommand);
- читать `/etc/shadow`, sudoers, ключи;
- выполнить `dnf`/`apt`/`systemctl`.

**Как работает SFTP-chroot:**

```
Клиент sftp svcsec@host
        │
        ▼
sshd Match User svcsec
  ChrootDirectory /opt/install     ← процесс «видит» это как /
  ForceCommand internal-sftp -d /staging
        │
        ▼
Реальный путь записи: /opt/install/staging/...
```

Требование OpenSSH: каталог chroot (`/opt/install`) должен принадлежать
`root:root` и **не** быть writable для пользователя. Writable — только
подкаталог `staging`.

Команда `super` — это **не** повышение привилегий само по себе. Это UX:
svcsec по sudoers может запустить сессию **от имени** svcsecadmin. Реальные
права — у svcsecadmin. SSH у svcsecadmin при этом закрыт (`DenyUsers`).

### 3.3. svcsecadmin — «единственный полный админ»

**Может всё**, что нужно ОС: пакеты, systemd, SELinux/PARSEC, пользователи,
sudoers, audit, firewall, установка Wazuh.

**Ограничение доступа:** нет SSH. Вход:
- локальная консоль / IPMI / KVM; или
- переход `svcsec → super → сессия svcsecadmin`.

Так снижается риск удалённого брутфорса/кражи ключа «супер-админа».

### 3.4. poinstall — «установщик приложений в песочнице»

**Может (через sudo whitelist):**
- запускать скрипты из `/opt/install/approved/*.sh`;
- раскладывать файлы в `/opt/apps/<app>/`;
- писать данные в `/var/opt/apps/<app>/` (раздел с **noexec**).

**Не может:**
- `dnf`/`yum`/`apt`/`dpkg`/`rpm`;
- `systemctl`;
- писать в `/var/ossec`, `/etc/systemd`, `/usr`, sudoers.

**Почему Wazuh не ставит poinstall:** агент — системный пакет с unit’ами,
пользователями, путями в `/var/ossec`. Это зона админа ОС. poinstall в примере
Wazuh ставит только **helpers** в `/opt/apps/wazuh-helpers`.

### 3.5. editor / timeditor — «хирургия конфигов»

**Может:**
- `sudoedit` только по whitelist (например `ossec.conf`);
- опционально узкий `systemctl restart wazuh-agent` и `status`.

**Не может:**
- `sudo bash`, `sudo vim`, `visudo`, `usermod`;
- общий `systemctl` (другие unit’ы).

**timeditor** = те же команды, но `NOPASSWD`, членство снимается через 8 часов
systemd-таймером. State-файл `/var/lib/rbac-timers/<user>` принадлежит root,
режим `0600` — пользователь не может сам продлить TTL, подделав файл.

---

## 4. Карта каталогов и зачем так

| Путь | Запись | Exec | Смысл |
|------|--------|------|-------|
| `/opt/install/staging` | svcsec (SFTP) | **noexec** (желательно) | карантин входящих файлов |
| `/opt/install/approved` | только admin | да (скрипты установки) | проверенные артефакты |
| `/opt/apps/<app>` | poinstall | да | self-contained приложения |
| `/var/opt/apps/<app>` | poinstall/app | **noexec** | данные (нельзя запустить upload как бинарь) |
| `/etc/opt/apps/<app>` | через sudoedit | нет | конфиги приложений |
| `/var/ossec` | пакетный менеджер (admin) | да (бинари пакета) | Wazuh — системный префикс |
| `/var/ossec/etc` | sudoedit (editor) | нет | конфиг агента |

Поток артефакта:

```
[поставщик]
    --SFTP-->  staging   (недоверенные файлы)
    --hash+approve (admin)-->  approved
         │                         │
         │                    self-contained → poinstall → /opt/apps
         │
         └── системный rpm/deb → svcsecadmin → /var/ossec + systemd
```

---

## 5. sudoers: как читать правила

Пример:

```
%editor ALL=(root) sudoedit /var/ossec/etc/ossec.conf
%editor ALL=(root) /usr/bin/systemctl restart wazuh-agent
```

Читается так:
- члены группы `editor`;
- на любом хосте (`ALL`);
- от имени `root`;
- могут выполнить **только** перечисленные команды.

Чего нет в списке — **запрещено** (default deny для sudo).

Теги:
- `NOPASSWD:` — без пароля (timeditor);
- `NOEXEC:` — запрет shell-escape из команды (если команда это поддерживает);
- `sudoedit` — специальный механизм, не путать с `sudo vim`.

Проверка прав пользователя:

```bash
sudo -l -U editor1
```

---

## 6. auditd: что смотреть

Правила вида:

```
-w /var/ossec/etc -p wa -k wazuh_conf
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/dnf -F key=pkg_mgr
```

- `-w путь` — watch на запись/атрибуты;
- `-k имя` — метка для поиска;
- `execve` на путь бинаря — фиксирует запуск.

Поиск:

```bash
ausearch -k wazuh_conf -ts recent
ausearch -k pkg_mgr -ts today
aureport -x --summary
```

На Astra дополнительно события коррелируются через **audisp-parsec**.

---

## 7. MAC кратко

### РЕД ОС — SELinux

Процессы и файлы имеют **типы** (контексты). Даже root в userspace ограничен
политикой в enforcing. После создания каталогов/`dnf install` нужен
`restorecon`. AVC denials смотрят через `ausearch -m avc`.

### Astra — PARSEC (МРД/МКЦ)

Мандатные уровни/категории на субъектах и объектах. Утилиты назначения меток
зависят от сборки SE 1.8 — см. чеклист `astra18/parsec/CHECKLIST.md`.
Смысл тот же: poinstall/editor не должны читать секреты ОС «по мандату»,
даже если ошибочно открыть DAC.

---

## 8. Типовые ошибки внедрения

| Ошибка | Почему плохо | Правильно |
|--------|--------------|-----------|
| Alias `alias dnf='echo no'` | UX, легко обойти | sudoers + MAC |
| `sudo vim` для conf | shell-escape | `sudoedit` |
| `noexec` на `/` | ломает ОС и Wazuh | noexec только на data/staging |
| poinstall ставит wazuh rpm | админ-права ОС | только svcsecadmin |
| Широкий `systemctl` editor’у | рестарт sshd и др. | узкий Cmnd_Alias |
| SSH открыт у svcsecadmin | кража ключа = полный захват | DenyUsers |

---

## 9. Связь с файлами репозитория

| Тема | Эталон в репо |
|------|----------------|
| Общий sudoers | `common/sudoers.d/00-rbac-common` |
| sshd | `common/sshd/50-rbac-roles.conf` |
| approve / super / timeditor | `common/scripts/` |
| РЕД ОС sudoers/audit | `redos8/` |
| Astra sudoers/audit/parsec | `astra18/` |

Далее: ручная настройка — [02-redos8-manual.md](02-redos8-manual.md) или
[03-astra18-manual.md](03-astra18-manual.md).
