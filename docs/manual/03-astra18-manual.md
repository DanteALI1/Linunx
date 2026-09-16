# Astra Linux SE 1.8 — поэтапная ручная настройка

> **Под какой УЗ работать:** [`05-who-runs-what.md`](05-who-runs-what.md).  
> **Справочник auditd:** [`06-auditd-rules-catalog.md`](06-auditd-rules-catalog.md).

Выполняйте от **указанной УЗ**. Имена утилит PARSEC сверяйте с руководством
вашей сборки SE 1.8.

Предварительно: [01-how-it-works.md](01-how-it-works.md). Эталоны: `astra18/`, `common/`.

---

## Этап 0. Инвентаризация и пакеты

**УЗ: `root` (консоль)** — bootstrap.

```bash
cat /etc/astra_version 2>/dev/null || cat /etc/os-release
uname -r
```

### 0.2. Пакеты

```bash
apt-get update
apt-get install -y sudo auditd openssh-server acl
# плагин PARSEC для audit — имя пакета уточните по документации, типично связано с audisp-parsec:
apt-cache search audisp-parsec || true
# apt-get install -y <пакет-audisp-parsec>
```

**Как работает отличие от РЕД ОС:** пакетный менеджер — `apt`/`dpkg`, пути
unit’ов часто `/lib/systemd/system`, MAC — **PARSEC**, не SELinux.

### 0.3. Время

```bash
timedatectl status || true
# ntp/chrony — по политике Astra
```

**Проверка**

```bash
dpkg -l sudo auditd openssh-server | grep ^ii
systemctl is-active ssh auditd || systemctl is-active sshd auditd
```

---

## Этап 1. Подтвердить MAC / MIC (PARSEC)

**УЗ: `root` / `svcsecadmin` (консоль)**

```bash
# Типовые проверки (зависят от сборки):
astra-modeswitch status 2>/dev/null || true
# pdp-ls -d / 2>/dev/null | head
# cat /proc/self/attr/current 2>/dev/null
```

**Цель этапа:** убедиться, что мандатный контроль **включён** согласно профилю
СЗИ. Не переводите систему в режим без MAC «для удобства установки».

Зафиксируйте в акте:
- профиль СЗИ / режим;
- кто имеет право менять метки (это будет только svcsecadmin).

Подробный чеклист меток: `astra18/parsec/CHECKLIST.md`.

---

## Этап 2. Группы и пользователи

**УЗ: `root` (консоль)** — создание ролей; далее админ-работы — `svcsecadmin`.

Команды те же по смыслу, что на РЕД ОС (useradd/groupadd — стандартные):

```bash
groupadd --system svcsec       2>/dev/null || true
groupadd --system svcsecadmin  2>/dev/null || true
groupadd --system poinstall    2>/dev/null || true
groupadd --system editor       2>/dev/null || true
groupadd --system timeditor    2>/dev/null || true

id svcsec 2>/dev/null || \
  useradd --system --create-home --home-dir /home/svcsec \
    --shell /bin/bash --gid svcsec -G svcsec svcsec

id svcsecadmin 2>/dev/null || \
  useradd --system --create-home --home-dir /home/svcsecadmin \
    --shell /bin/bash --gid svcsecadmin -G svcsecadmin,sudo svcsecadmin
# На Astra часто группа sudo вместо wheel

id poinstaller 2>/dev/null || \
  useradd -m -s /bin/bash -g poinstall -G poinstall poinstaller
id editor1 2>/dev/null || \
  useradd -m -s /bin/bash -g editor -G editor editor1

install -d -o svcsec -g svcsec -m 0700 /home/svcsec/.ssh
touch /home/svcsec/.ssh/authorized_keys
chown svcsec:svcsec /home/svcsec/.ssh/authorized_keys
chmod 0600 /home/svcsec/.ssh/authorized_keys
# вставить pubkey поставщика

passwd svcsecadmin   # консоль
passwd poinstaller
passwd editor1
```

### Назначение мандатных атрибутов УЗ (шаблон)

```bash
# ПРИМЕР — замените уровни на принятые в орг. политике:
# pdpl-user -l <уровень_поставки> svcsec
# pdpl-user -l <уровень_приложений> poinstaller
# pdpl-user -l <уровень_приложений> editor1
# pdpl-user -l <админ_уровень> svcsecadmin
```

**Как работает:** даже при ошибке в DAC мандат не даст poinstall/editor читать
объекты с более высоким уровнем (shadow, ключи, части /etc).

**Проверка**

```bash
id svcsec; id svcsecadmin; id poinstaller; id editor1
# утилита просмотра меток пользователя — по документации Astra
```

---

## Этап 3. Каталоги, ACL, noexec

**УЗ: `root` / `svcsecadmin` (консоль)**

Идентично РЕД ОС по путям и правам:

```bash
install -d -o root -g root      -m 0755 /opt/install
install -d -o root -g svcsec    -m 1770 /opt/install/staging
install -d -o root -g root      -m 0750 /opt/install/approved
install -d -o root -g poinstall -m 0770 /opt/apps
install -d -o root -g poinstall -m 0770 /var/opt/apps
install -d -o root -g root      -m 0755 /etc/opt/apps
install -d -o root -g poinstall -m 0770 /opt/apps/wazuh-helpers
install -d -o root -g poinstall -m 0770 /var/opt/apps/wazuh-helpers
install -d -o root -g root      -m 0750 /etc/opt/apps/wazuh-helpers
install -d -o root -g root      -m 0750 /var/lib/rbac-timers
install -d -o root -g root      -m 0750 /var/log/rbac
install -d -o root -g root      -m 0750 /usr/local/sbin

setfacl -m u:svcsec:rwx,g:svcsec:rwx,g:svcsecadmin:rwx,o::--- /opt/install/staging
setfacl -d -m u:svcsec:rwx,g:svcsec:rwx,g:svcsecadmin:rwx,o::--- /opt/install/staging
setfacl -m g:poinstall:rx,g:svcsecadmin:rwx,o::--- /opt/install/approved
setfacl -m g:poinstall:rwx,g:svcsecadmin:rwx /opt/apps
setfacl -d -m g:poinstall:rwx /opt/apps
setfacl -m g:poinstall:rwx /var/opt/apps
```

**Метки PARSEC на каталогах** (после создания):

```bash
# setfilelev / pdpl-file — по вашей версии, например:
# назначить staging уровень поставки, /opt/apps — прикладной,
# /var/ossec позже — уровень служб мониторинга
```

`noexec` на `/var/opt/apps` — через fstab, **не** на `/`.

**Проверка**

```bash
getfacl /opt/install/staging
su -s /bin/bash svcsec -c 'touch /opt/install/staging/t && rm /opt/install/staging/t'
su -s /bin/bash poinstaller -c 'touch /opt/install/approved/x'  # FAIL ожидается
```

---

## Этап 4. Бинарники управления

**УЗ: `svcsecadmin` (консоль)**

```bash
install -o root -g root -m 0750 common/scripts/svcsec-super        /usr/local/sbin/svcsec-super
install -o root -g root -m 0750 common/scripts/svcsecadmin-session /usr/local/sbin/svcsecadmin-session
install -o root -g root -m 0750 common/scripts/approve-artifact    /usr/local/sbin/approve-artifact
install -o root -g root -m 0750 common/scripts/timeditor-grant.sh  /usr/local/sbin/timeditor-grant
install -o root -g root -m 0750 common/scripts/timeditor-expire.sh /usr/local/sbin/timeditor-expire
install -o root -g root -m 0750 astra18/scripts/install-wazuh-agent-astra.sh \
  /usr/local/sbin/install-wazuh-agent-astra
```

Смысл бинарей — как в руководстве РЕД ОС (`02-redos8-manual.md`, этап 4):
`super` / `approve` / `timeditor-*` / установщик Wazuh под Astra (`apt`/`dpkg`).

После копирования при необходимости **переназначьте метки PARSEC** на
`/usr/local/sbin/*`, иначе мандат может запретить запуск от svcsecadmin.

---

## Этап 5. sudoers

**УЗ: `svcsecadmin` / `root` (консоль; держите root-сессию!)**

```bash
install -o root -g root -m 0440 common/sudoers.d/00-rbac-common \
  /etc/sudoers.d/00-rbac-common
install -o root -g root -m 0440 astra18/sudoers.d/10-rbac-poinstall-astra \
  /etc/sudoers.d/10-rbac-poinstall-astra
install -o root -g root -m 0440 astra18/sudoers.d/20-rbac-editor-wazuh-astra \
  /etc/sudoers.d/20-rbac-editor-wazuh-astra

visudo -cf /etc/sudoers
visudo -cf /etc/sudoers.d/00-rbac-common
visudo -cf /etc/sudoers.d/10-rbac-poinstall-astra
visudo -cf /etc/sudoers.d/20-rbac-editor-wazuh-astra
```

Отличие файла poinstall от РЕД ОС: deny на `apt`/`apt-get`/`dpkg` вместо `dnf`/`rpm`,
плюс запрет утилит PARSEC (`pdpl-user` и т.п.) для poinstall.

```bash
sudo -l -U svcsec
sudo -l -U poinstaller
sudo -l -U editor1

su - poinstaller -c 'sudo -n apt-get --version'  # DENY
su - editor1 -c 'sudo -n bash -c id'             # DENY
```

---

## Этап 6. SSH / SFTP

**УЗ настройки: `svcsecadmin`** · проверка: ключ **svcsec** с рабочей станции


```bash
install -d /etc/ssh/sshd_config.d
install -o root -g root -m 0644 common/sshd/50-rbac-roles.conf \
  /etc/ssh/sshd_config.d/50-rbac-roles.conf

sshd -t
systemctl reload ssh || systemctl reload sshd
```

Тесты:

```bash
sftp svcsec@<server>           # OK → /staging
ssh svcsecadmin@<server>       # DENY
ssh -tt svcsec@<server>        # не bash
```

На Astra дополнительно убедитесь, что метки home/`.ssh` позволяют svcsec
аутентифицироваться по ключу (иначе sshd откажет до Match).

---

## Этап 7. auditd + audisp-parsec

**УЗ: `svcsecadmin` (консоль)**  
Каталог всех правил: [`06-auditd-rules-catalog.md`](06-auditd-rules-catalog.md).

```bash
install -o root -g root -m 0640 common/audit/00-base.rules /etc/audit/rules.d/00-base.rules
install -o root -g root -m 0640 common/audit/10-hardening-common.rules /etc/audit/rules.d/10-hardening-common.rules
install -o root -g root -m 0640 common/audit/10-hardening-syscalls.rules /etc/audit/rules.d/10-hardening-syscalls.rules
install -o root -g root -m 0640 astra18/audit/11-hardening-astra.rules /etc/audit/rules.d/11-hardening-astra.rules
install -o root -g root -m 0640 astra18/audit/50-rbac-astra.rules /etc/audit/rules.d/50-rbac-astra.rules

# Плагин PARSEC:
install -d /etc/audisp/plugins.d
install -o root -g root -m 0644 astra18/audit/audisp-parsec.conf \
  /etc/audisp/plugins.d/audisp-parsec.conf
# Проверьте путь бинаря path= в conf — он должен существовать:
# ls -l /sbin/audisp-parsec

augenrules --load || systemctl restart auditd
systemctl enable --now auditd

grep -E '^active' /etc/audisp/plugins.d/audisp-parsec.conf
# active = yes
```

**Как работает audisp-parsec:** auditd передаёт события плагину; PARSEC
коррелирует их с мандатными решениями. Без плагина у вас останется «голый»
audit без полной картины MAC-denials.

Самотест:

```bash
ausearch -k install_staging -ts recent | tail
ausearch -k parsec_admin -ts recent | tail
```

---

## Этап 8. Timer timeditor

**УЗ: `svcsecadmin`** (enable timer); `timeditor-grant` — тоже только svcsecadmin

```bash
install -o root -g root -m 0644 common/systemd/timeditor-expire.service \
  /etc/systemd/system/timeditor-expire.service
install -o root -g root -m 0644 common/systemd/timeditor-expire.timer \
  /etc/systemd/system/timeditor-expire.timer
systemctl daemon-reload
systemctl enable --now timeditor-expire.timer
systemctl list-timers | grep timeditor
```

Проверка grant/expire — как в руководстве РЕД ОС (этап 8).

> После `usermod`/`gpasswd` на Astra проверьте, что мандатные атрибуты УЗ
> не сбросились политикой — при необходимости повторите `pdpl-user`.

---

## Этап 9. Согласование меток с политикой

**УЗ: `svcsecadmin`**

Пройдите чеклист `astra18/parsec/CHECKLIST.md` целиком:

1. Уровни УЗ ролей назначены.  
2. Каталоги RBAC промаркированы.  
3. Секреты ОС недоступны poinstall/editor по мандату.  
4. После будущей установки Wazuh — метки `/var/ossec` проверены.  

**Проверка denial’ов:** журналы PARSEC (путь зависит от сборки) + `ausearch`.
Блокирующих denials для штатных операций ролей быть не должно; для
запрещённых операций (чтение shadow) — denial **ожидаем и желателен**.

---

## Этап 10. Приёмка базы (без Wazuh)

**УЗ: `svcsecadmin`** (+ `su` на ролевые УЗ для negative-тестов)

- [ ] MAC/MIC активны по профилю СЗИ  
- [ ] sudoers parsed OK; negative-тесты poinstall/editor пройдены  
- [ ] SFTP svcsec OK; SSH svcsecadmin DENY  
- [ ] auditd active; audisp-parsec `active = yes`  
- [ ] timeditor timer работает  
- [ ] метки каталогов/УЗ соответствуют политике  

Далее: [04-wazuh-manual.md](04-wazuh-manual.md) (раздел Astra).

Rollback: `rollback/rollback-astra18.md`.
