# РЕД ОС 8 — поэтапная ручная настройка

Выполняйте от **root** на консоли (или от существующего админа до появления
`svcsecadmin`). После каждого этапа есть блок **Проверка**.

Эталонные файлы лежат в репозитории (`redos8/`, `common/`) — копируйте их
содержимое вручную или сверяйте построчно.

Предварительно прочитайте [01-how-it-works.md](01-how-it-works.md).

---

## Этап 0. Инвентаризация и пакеты

### 0.1. Убедиться, что это РЕД ОС 8

```bash
cat /etc/redos-release 2>/dev/null || cat /etc/os-release
uname -r
```

**Зачем:** команды пакетов (`dnf`) и пути SELinux отличаются от Astra (`apt`).

### 0.2. Установить необходимый софт

```bash
dnf install -y sudo audit audit-libs policycoreutils policycoreutils-python-utils \
  setools-console openssh-server acl libacl chrony
# опционально:
dnf install -y setroubleshoot-server fapolicyd
```

**Как работает:**
- `sudo` — механизм делегирования команд;
- `audit` — ядро пишет события в auditd;
- `policycoreutils*` / `setools` — управление SELinux;
- `acl` — расширенные ACL (`setfacl`), точнее DAC на каталогах.

### 0.3. Время и hostname (для корректных логов)

```bash
timedatectl status
hostnamectl
# при необходимости:
# timedatectl set-ntp true
```

**Проверка**

```bash
rpm -q sudo audit openssh-server
systemctl is-enabled sshd auditd
```

---

## Этап 1. SELinux → enforcing

### 1.1. Текущий режим

```bash
getenforce
sestatus
```

Ожидание для приёмки: `Enforcing`.

### 1.2. Включить постоянно

```bash
# сразу (до перезагрузки):
setenforce 1

# постоянно:
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
grep ^SELINUX= /etc/selinux/config
```

**Как работает:**  
`setenforce 1` меняет режим ядра сейчас. Файл `/etc/selinux/config` задаёт
режим после reboot. В `Permissive` AVC пишутся, но не блокируют — для боя
недостаточно.

**Проверка**

```bash
getenforce   # Enforcing
```

---

## Этап 2. Группы и пользователи

### 2.1. Группы ролей

```bash
groupadd --system svcsec        2>/dev/null || true
groupadd --system svcsecadmin   2>/dev/null || true
groupadd --system poinstall     2>/dev/null || true
groupadd --system editor        2>/dev/null || true
groupadd --system timeditor     2>/dev/null || true
getent group svcsec svcsecadmin poinstall editor timeditor
```

**Как работает:** Unix-группы — «бирки» для sudoers (`%editor`) и ACL.
Сама группа не даёт root; даёт только то, что прописано в sudoers/ACL.

### 2.2. Пользователь svcsec

```bash
id svcsec 2>/dev/null || \
  useradd --system --create-home --home-dir /home/svcsec \
    --shell /bin/bash --gid svcsec -G svcsec svcsec

install -d -o svcsec -g svcsec -m 0700 /home/svcsec/.ssh
touch /home/svcsec/.ssh/authorized_keys
chown svcsec:svcsec /home/svcsec/.ssh/authorized_keys
chmod 0600 /home/svcsec/.ssh/authorized_keys
```

Вставьте **публичный** ключ поставщика в `authorized_keys`:

```bash
echo 'ssh-ed25519 AAAA... svcsec-supply' >> /home/svcsec/.ssh/authorized_keys
```

**Почему shell bash, а не nologin:** Match в sshd всё равно заменит сессию на
`internal-sftp`. Локально bash может понадобиться только если политика разрешает
console-вход svcsec (обычно нет). Главный контроль — sshd `ForceCommand`.

### 2.3. Пользователь svcsecadmin

```bash
id svcsecadmin 2>/dev/null || \
  useradd --system --create-home --home-dir /home/svcsecadmin \
    --shell /bin/bash --gid svcsecadmin -G svcsecadmin,wheel svcsecadmin

# Задать пароль ТОЛЬКО для консоли / su (не для SSH — SSH запретим):
passwd svcsecadmin
```

**Как работает:** членство в `wheel` часто нужно для pam_wheel/`sudo` ALL на
РЕД ОС. Фактические права уточним в sudoers. SSH позже закроем через
`DenyUsers svcsecadmin`.

### 2.4. Прикладные пользователи (пример)

```bash
id poinstaller 2>/dev/null || \
  useradd -m -s /bin/bash -g poinstall -G poinstall poinstaller
id editor1 2>/dev/null || \
  useradd -m -s /bin/bash -g editor -G editor editor1

passwd poinstaller
passwd editor1
```

**Проверка**

```bash
id svcsec; id svcsecadmin; id poinstaller; id editor1
```

---

## Этап 3. Каталоги, права, ACL, mount

### 3.1. Создать дерево

```bash
install -d -o root -g root     -m 0755 /opt/install
install -d -o root -g svcsec   -m 1770 /opt/install/staging
install -d -o root -g root     -m 0750 /opt/install/approved
install -d -o root -g poinstall -m 0770 /opt/apps
install -d -o root -g poinstall -m 0770 /var/opt/apps
install -d -o root -g root     -m 0755 /etc/opt/apps
install -d -o root -g poinstall -m 0770 /opt/apps/wazuh-helpers
install -d -o root -g poinstall -m 0770 /var/opt/apps/wazuh-helpers
install -d -o root -g root     -m 0750 /etc/opt/apps/wazuh-helpers
install -d -o root -g root     -m 0750 /var/lib/rbac-timers
install -d -o root -g root     -m 0750 /var/log/rbac
install -d -o root -g root     -m 0750 /usr/local/sbin
```

**Разбор прав staging `1770`:**
- `1` — sticky bit: удалять чужие файлы нельзя (как в `/tmp`);
- `770` — владелец/группа пишут, others — нет;
- группа `svcsec` — чтобы SFTP-пользователь писал в каталог.

**Почему `/opt/install` = `root:root 755`:** требование `ChrootDirectory` в OpenSSH.
Если сделать его writable для svcsec, sshd **откажет** chroot.

### 3.2. ACL

```bash
setfacl -m u:svcsec:rwx,g:svcsec:rwx,g:svcsecadmin:rwx,o::--- /opt/install/staging
setfacl -d -m u:svcsec:rwx,g:svcsec:rwx,g:svcsecadmin:rwx,o::--- /opt/install/staging

setfacl -m g:poinstall:rx,g:svcsecadmin:rwx,o::--- /opt/install/approved
setfacl -m g:poinstall:rwx,g:svcsecadmin:rwx /opt/apps
setfacl -d -m g:poinstall:rwx /opt/apps
setfacl -m g:poinstall:rwx /var/opt/apps
setfacl -d -m g:poinstall:rwx /var/opt/apps

getfacl /opt/install/staging
getfacl /opt/install/approved
```

**Как работает ACL:** поверх классического `rwx` даёт точечные права группе
`svcsecadmin` на staging (для approve) и `poinstall` — чтение approved без записи.

### 3.3. noexec на данных (важно)

**Нельзя** ставить `noexec` на `/`. Только на data/staging.

Пример, если `/var/opt/apps` — отдельный раздел (подставьте свой UUID):

```bash
# blkid
# в /etc/fstab:
# UUID=....  /var/opt/apps  xfs  defaults,nodev,nosuid,noexec  0 2
# mount -a
mount | grep /var/opt/apps
```

Если отдельного раздела нет — зафиксируйте риск в модели угроз и хотя бы
закройте exec политикой SELinux/fapolicyd; при первой возможности вынесите FS.

**Проверка**

```bash
namei -l /opt/install/staging
namei -l /opt/install/approved
# от пользователя:
su -s /bin/bash svcsec -c 'touch /opt/install/staging/test_svcsec && rm /opt/install/staging/test_svcsec'
su -s /bin/bash poinstaller -c 'touch /opt/install/approved/should_fail'   # должна быть ошибка
```

---

## Этап 4. Бинарники управления (super, approve, timeditor)

Скопируйте из репозитория и установите:

```bash
# из каталога клона репозитория:
install -o root -g root -m 0750 common/scripts/svcsec-super           /usr/local/sbin/svcsec-super
install -o root -g root -m 0750 common/scripts/svcsecadmin-session    /usr/local/sbin/svcsecadmin-session
install -o root -g root -m 0750 common/scripts/approve-artifact       /usr/local/sbin/approve-artifact
install -o root -g root -m 0750 common/scripts/timeditor-grant.sh     /usr/local/sbin/timeditor-grant
install -o root -g root -m 0750 common/scripts/timeditor-expire.sh    /usr/local/sbin/timeditor-expire
install -o root -g root -m 0750 redos8/scripts/install-wazuh-agent-redos.sh \
  /usr/local/sbin/install-wazuh-agent-redos
```

### Что делает каждый

| Бинарь | Кто вызывает | Смысл |
|--------|--------------|-------|
| `svcsec-super` | svcsec через sudo → svcsecadmin | UX входа в админ-сессию |
| `svcsecadmin-session` | только из super | interactive/exec-обёртка с логом |
| `approve-artifact` | svcsecadmin | sha256 + staging→approved + удаление из staging |
| `timeditor-grant` | svcsecadmin | выдать группу на 8ч + state-файл |
| `timeditor-expire` | systemd timer | снять просроченных |
| `install-wazuh-agent-redos` | svcsecadmin | dnf install + address + enable |

Создайте удобный UX для svcsec (это **не СЗИ**, только удобство):

```bash
install -d -o svcsec -g svcsec -m 0755 /home/svcsec/bin
cat >/home/svcsec/bin/super <<'EOF'
#!/bin/bash
exec sudo -u svcsecadmin /usr/local/sbin/svcsec-super "$@"
EOF
chown svcsec:svcsec /home/svcsec/bin/super
chmod 0755 /home/svcsec/bin/super
```

> На практике svcsec по SSH **не получит shell** (ForceCommand sftp).  
> `super` используют с консоли или отдельного Jump-сценария, где svcsec
> допускается локально. Контроль права — **sudoers**, не alias.

**Проверка**

```bash
ls -l /usr/local/sbin/svcsec-super /usr/local/sbin/approve-artifact
```

---

## Этап 5. sudoers

### 5.1. Подключить файлы

```bash
install -o root -g root -m 0440 common/sudoers.d/00-rbac-common \
  /etc/sudoers.d/00-rbac-common
install -o root -g root -m 0440 redos8/sudoers.d/10-rbac-poinstall-redos \
  /etc/sudoers.d/10-rbac-poinstall-redos
install -o root -g root -m 0440 redos8/sudoers.d/20-rbac-editor-wazuh-redos \
  /etc/sudoers.d/20-rbac-editor-wazuh-redos
```

### 5.2. Обязательная проверка синтаксиса

```bash
visudo -cf /etc/sudoers
visudo -cf /etc/sudoers.d/00-rbac-common
visudo -cf /etc/sudoers.d/10-rbac-poinstall-redos
visudo -cf /etc/sudoers.d/20-rbac-editor-wazuh-redos
```

Ожидание: `parsed OK`. Ошибка синтаксиса может **заблокировать sudo** —
держите root-консоль открытой.

### 5.3. Что внутри (логика)

**00-rbac-common**
- логирование sudo (`logfile`, `iolog`);
- svcsec → только `RBAC_SUPER` от имени svcsecadmin;
- svcsecadmin → `ALL`;
- запрет shell/vim через sudo для poinstall/editor/timeditor.

**10-…-poinstall**
- whitelist скриптов approved и бинарей `/opt/apps/...`;
- явный deny `dnf`/`systemctl`.

**20-…-editor-wazuh**
- `sudoedit` на `ossec.conf` (+ app conf);
- только `systemctl restart|status wazuh-agent`.

### 5.4. Просмотр глазами пользователя

```bash
sudo -l -U svcsec
sudo -l -U svcsecadmin
sudo -l -U poinstaller
sudo -l -U editor1
```

**Проверка negative (сейчас, до Wazuh тоже полезно)**

```bash
su - editor1 -c 'sudo -n bash -c id'          # отказано
su - poinstaller -c 'sudo -n dnf --version'   # отказано
```

---

## Этап 6. SSH / SFTP

### 6.1. Drop-in конфиг

```bash
install -d /etc/ssh/sshd_config.d
install -o root -g root -m 0644 common/sshd/50-rbac-roles.conf \
  /etc/ssh/sshd_config.d/50-rbac-roles.conf
```

Содержимое по смыслу:

```
DenyUsers svcsecadmin

Match User svcsec
    ForceCommand internal-sftp -d /staging
    ChrootDirectory /opt/install
    AllowTcpForwarding no
    X11Forwarding no
    PermitTTY no
    PasswordAuthentication no
    PubkeyAuthentication yes
```

**Как работает Match:** для пользователя svcsec sshd **игнорирует** обычный
shell и запускает только sftp-сервер внутри chroot. `DenyUsers` отсекает
svcsecadmin до аутентификации сессии.

### 6.2. Проверка и reload

```bash
sshd -t && systemctl reload sshd
```

### 6.3. Тесты с рабочей станции

```bash
# Должно открыть sftp, путь /staging:
sftp svcsec@<server>

# Должно получить отказ / disconnect:
ssh svcsecadmin@<server>

# Обычный ssh svcsec — не должен дать bash:
ssh svcsec@<server>
```

---

## Этап 7. auditd

### 7.1. Установить правила

```bash
install -o root -g root -m 0640 redos8/audit/50-rbac-redos.rules \
  /etc/audit/rules.d/50-rbac-redos.rules

augenrules --load
# или:
# systemctl restart auditd
```

### 7.2. Включить службу и логи sudo

```bash
systemctl enable --now auditd
touch /var/log/sudo.log
chmod 0600 /var/log/sudo.log
```

### 7.3. Быстрый самотест правил

```bash
# сгенерировать событие:
ls /opt/install/staging >/dev/null
ausearch -k install_staging -ts recent | tail

auditctl -l | head
```

**Как работает:** `augenrules` собирает файлы из `rules.d` в `/etc/audit/audit.rules`
и загружает в ядро. Ключи `-k` нужны, чтобы потом не искать «иголку» в сыром логе.

---

## Этап 8. systemd timer для timeditor

```bash
install -o root -g root -m 0644 common/systemd/timeditor-expire.service \
  /etc/systemd/system/timeditor-expire.service
install -o root -g root -m 0644 common/systemd/timeditor-expire.timer \
  /etc/systemd/system/timeditor-expire.timer

systemctl daemon-reload
systemctl enable --now timeditor-expire.timer
systemctl list-timers | grep timeditor
```

**Проверка цикла вручную**

```bash
/usr/local/sbin/timeditor-grant editor1
id editor1   # должен быть timeditor
# эмуляция истечения:
sed -i "s/^expire_epoch=.*/expire_epoch=1/" /var/lib/rbac-timers/editor1
/usr/local/sbin/timeditor-expire
id editor1   # timeditor снят
# вернуть нормальный grant при необходимости
```

---

## Этап 9. SELinux контексты каталогов

```bash
restorecon -Rv /opt/install /opt/apps /var/opt/apps /usr/local/sbin
# после установки Wazuh — обязательно:
# restorecon -Rv /var/ossec

ausearch -m avc -ts recent | tail || echo "no recent AVC"
```

Подробности и booleans: `redos8/selinux/CHECKLIST.md`.

**Не делайте** `setenforce 0` «чтобы заработало». Разбирайте AVC → `audit2allow`
точечно, документируя каждое allow.

---

## Этап 10. (Опционально) fapolicyd

```bash
# установить правила из redos8/fapolicyd/70-rbac-apps.rules
# fapolicyd-cli --update
# systemctl enable --now fapolicyd
```

Включайте только после проверки, что `/opt/apps` и `/var/ossec/bin` не ломаются.

---

## Этап 11. Приёмка базовой настройки (без Wazuh)

Чеклист:

- [ ] `getenforce` = Enforcing  
- [ ] `visudo -cf` OK на всех drop-in  
- [ ] `sshd -t` OK; SFTP svcsec работает; SSH svcsecadmin — нет  
- [ ] `auditd` active; `ausearch -k install_staging` видит доступ  
- [ ] poinstall **не** может `sudo dnf` / `sudo systemctl`  
- [ ] editor **не** может `sudo bash` / `sudo vim`  
- [ ] timer `timeditor-expire` в списке timers  

Далее — ручной прогон Wazuh: [04-wazuh-manual.md](04-wazuh-manual.md)
(раздел «РЕД ОС 8»).

---

## Этап 12. Rollback (если нужно откатить только RBAC)

См. `rollback/rollback-redos8.md`. Кратко: удалить drop-in sudoers/sshd/audit,
`visudo -cf`, reload sshd, не удалять svcsecadmin пока нет другого админ-доступа.
