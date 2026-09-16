# Ручной прогон: Wazuh Agent end-to-end

Документ предполагает, что базовая RBAC-настройка уже выполнена вручную:
- РЕД ОС 8 → [02-redos8-manual.md](02-redos8-manual.md)
- Astra SE 1.8 → [03-astra18-manual.md](03-astra18-manual.md)

Цель: показать **рабочий агент** и **несмешанные роли** на реальных командах.

---

## 0. Подготовка артефактов (на машине поставщика)

Скачайте официальный пакет под вашу ОС:

| ОС | Пакет |
|----|-------|
| РЕД ОС 8 | `wazuh-agent-<ver>.x86_64.rpm` |
| Astra SE 1.8 | `wazuh-agent-<ver>_amd64.deb` (или актуальная арх.) |

Создайте checksum:

```bash
# пример для rpm:
sha256sum wazuh-agent-4.x.x-1.x86_64.rpm | tee wazuh-agent-4.x.x-1.x86_64.rpm.sha256
cat wazuh-agent-4.x.x-1.x86_64.rpm.sha256
# строка вида:
# <64 hex>  wazuh-agent-4.x.x-1.x86_64.rpm
```

Подготовьте данные менеджера (документ для оператора):

```
MANAGER_ADDRESS=10.20.30.40
PORT=1514/tcp
PROTOCOL=tcp
```

Опционально: шаблон фрагмента conf — `playbooks/ossec.conf.template.snippet`.

---

## 1. РОЛЬ svcsec — загрузка в staging

### 1.1. Подключение

```bash
sftp -i ~/.ssh/svcsec_key svcsec@<server>
```

**Что должно произойти:** открывается SFTP, текущий каталог — `/staging`
(внутри chroot это видно как `/staging`, реально `/opt/install/staging`).

**Чего не должно быть:** приглашения bash (`$`), возможности `cd /etc`.

### 1.2. Загрузка файлов

```text
sftp> put wazuh-agent-4.x.x-1.x86_64.rpm
sftp> put wazuh-agent-4.x.x-1.x86_64.rpm.sha256
sftp> ls -l
sftp> bye
```

Для Astra — те же шаги с `.deb`.

### 1.3. Почему это безопасно

| Контроль | Эффект |
|----------|--------|
| ForceCommand internal-sftp | нет shell-escape по SSH |
| Chroot `/opt/install` | нет доступа к `/etc`, `/root`, `/var/ossec` |
| staging noexec / политика | загруженный rpm нельзя «запустить» как скрипт из staging |
| Нет sudo dnf у svcsec | пакет сам не установится |

### 1.4. Negative tests (svcsec)

```bash
ssh svcsec@<server> 'id'                 # не должен выполнить как shell
ssh svcsecadmin@<server>                 # DENY
# если есть локальный shell у svcsec (консоль) — всё равно:
sudo -n dnf --version                    # DENY
```

### 1.5. Audit

На сервере (admin):

```bash
ausearch -k install_staging -ts recent | tail -n 20
ls -la /opt/install/staging/
```

---

## 2. Переход к svcsecadmin (`super`)

С консоли или разрешённого канала:

```bash
# от svcsec (если локальный вход разрешён политикой):
sudo -u svcsecadmin /usr/local/sbin/svcsec-super
# либо UX:
# ~/bin/super
```

**Что происходит внутри:**
1. sudoers позволяет svcsec запустить **только** этот бинарь от имени svcsecadmin.
2. `svcsec-super` проверяет, что эффективный пользователь — svcsecadmin.
3. Запускается `svcsecadmin-session` (login shell или `--exec`).
4. В лог пишется событие с ключом `svcsec_super`.

```bash
ausearch -k svcsec_super -ts recent
# или:
grep svcsec-super /var/log/messages /var/log/syslog 2>/dev/null | tail
```

Дальнейшие шаги — **уже от svcsecadmin/root**.

---

## 3. РОЛЬ svcsecadmin — проверка, approve, установка, запуск

### 3.1. Проверка целостности и перенос в approved

```bash
cd /opt/install/staging
ls -la wazuh-agent-*

/usr/local/sbin/approve-artifact /opt/install/staging/wazuh-agent-4.x.x-1.x86_64.rpm
```

**Алгоритм approve-artifact:**
1. Проверяет, что файл реально под `/opt/install/staging` (защита от path traversal).
2. Сверяет SHA256 с sidecar-файлом.
3. Копирует в `/opt/install/approved/` с правами `root:root 0640`.
4. **Удаляет** оригинал из staging (нельзя «подменить после hash»).

```bash
ls -la /opt/install/approved/
ausearch -k artifact_approve -ts recent
```

Ожидание: файл есть в approved, в staging — исчез.

### 3.2. Установка пакета

#### РЕД ОС 8

```bash
# вариант A — готовый скрипт:
/usr/local/sbin/install-wazuh-agent-redos 10.20.30.40

# вариант B — вручную по шагам (для понимания):
dnf -y install /opt/install/approved/wazuh-agent-4.x.x-1.x86_64.rpm
```

**Что делает dnf:** распаковывает файлы в `/var/ossec`, создаёт УЗ/группу wazuh,
кладёт unit `wazuh-agent.service`, скрипты в `/var/ossec/bin`.  
Это **изменение системы** — поэтому только svcsecadmin.

#### Astra SE 1.8

```bash
/usr/local/sbin/install-wazuh-agent-astra 10.20.30.40

# вручную:
apt-get update -y || true
apt-get install -y /opt/install/approved/wazuh-agent-4.x.x_amd64.deb
# или: dpkg -i ... && apt-get -f install -y
```

После apt на Astra — **метки PARSEC** на `/var/ossec` по чеклисту.

### 3.3. Первичная запись адреса менеджера

Скрипт установки делает `sed` по `<address>`. Вручную:

```bash
grep -n '<address>' /var/ossec/etc/ossec.conf
# Заменить на адрес менеджера (как root/svcsecadmin):
sed -i 's#<address>.*</address>#<address>10.20.30.40</address>#' /var/ossec/etc/ossec.conf
grep -A3 '<server>' /var/ossec/etc/ossec.conf
```

**Почему первичную запись делает admin, а не editor:**  
нужно поднять агент «с нуля» до рабочего состояния. Дальнейшие штатные правки
конфига — зона editor через sudoedit (разделение обязанностей).

### 3.4. SELinux / PARSEC после установки

**РЕД ОС:**

```bash
restorecon -Rv /var/ossec
ausearch -m avc -ts recent | grep -i wazuh || echo "no wazuh AVC"
```

**Astra:**

```bash
# назначить/проверить метки /var/ossec по политике
# убедиться в отсутствии блокирующих PARSEC denials при старте
```

### 3.5. Запуск службы

```bash
systemctl enable --now wazuh-agent
systemctl status wazuh-agent --no-pager
systemctl is-active wazuh-agent    # active
systemctl is-enabled wazuh-agent   # enabled
```

**Как работает unit:** systemd запускает процессы Wazuh (agentd, logcollector,
syscheck и т.д.) от служебного пользователя с нужными capabilities/MAC.

### 3.6. Проверка логов и сети

```bash
tail -n 50 /var/ossec/logs/ossec.log
# Признаки нормального старта: отсутствие permission denied на conf/logs,
# попытки связи с менеджером (connected / unable to connect — второе значит
# сетевой/firewall вопрос, но права ОС в порядке).

# Порты (исходящие обычно 1514/tcp к менеджеру):
ss -tnp | grep -i wazuh || true
```

Firewall — **только svcsecadmin**, и только если политика требует явного
разрешения исходящих.

### 3.7. Audit установки

```bash
ausearch -k pkg_mgr -ts recent | tail
ausearch -k systemctl -ts recent | tail
ausearch -k wazuh_conf -ts recent | tail
```

### 3.8. Закрепить DAC на conf (editor пишет только через sudoedit)

```bash
ls -la /var/ossec/etc/ossec.conf
# ожидаемо что-то вроде: -rw-r----- root wazuh
# НЕ добавляйте editor1 в ACL на запись этого файла!
```

**Почему:** если дать DAC-write, editor обойдёт sudoers/sudoedit и аудит sudo.
Правильный путь — отсутствие прямой записи + sudoedit.

---

## 4. РОЛЬ poinstall — только helpers (и negative)

### 4.1. Подготовить helper в approved (делает admin)

```bash
install -o root -g root -m 0750 playbooks/install-wazuh-helpers.sh \
  /opt/install/approved/install-wazuh-helpers.sh
```

### 4.2. Установка helpers от poinstaller

```bash
su - poinstaller -c 'sudo /opt/install/approved/install-wazuh-helpers.sh'
ls -la /opt/apps/wazuh-helpers/bin/
```

**Что получили:** скрипты в `/opt/apps/...`, без изменения rpm/deb базы и без
unit’ов.

### 4.3. Negative tests (обязательно)

```bash
su - poinstaller -c 'sudo dnf install /opt/install/approved/wazuh-agent-*.rpm'
# РЕД ОС → DENY

su - poinstaller -c 'sudo apt-get install wazuh-agent'
# Astra → DENY

su - poinstaller -c 'sudo systemctl restart wazuh-agent'
# DENY

su - poinstaller -c 'touch /var/ossec/etc/pwned'
# DENY (permission denied)

su - poinstaller -c 'sudo systemctl status sshd'
# DENY
```

Фиксация:

```bash
grep poinstaller /var/log/sudo.log | tail
ausearch -k sudo_exec -ts recent | grep poinstaller | tail
```

---

## 5. РОЛЬ editor — правка conf и узкий restart

### 5.1. Посмотреть права sudo

```bash
su - editor1 -c 'sudo -l'
# должны быть видны sudoedit .../ossec.conf и systemctl restart|status wazuh-agent
```

### 5.2. Редактирование через sudoedit

```bash
su - editor1 -c 'sudoedit /var/ossec/etc/ossec.conf'
```

**Что происходит технически:**
1. sudo копирует файл во временный в `/var/tmp` (или аналог) с правами editor1.
2. Открывается редактор **без привилегий root** (`Defaults editor=...`).
3. После сохранения sudo сравнивает и атомарно заменяет оригинал от root.
4. Shell-escape из редактора даёт только права editor1, не root.

Внесите безопасное изменение для проверки (например комментарий XML или
проверка, что `<address>` верный). Сохраните.

### 5.3. Restart только wazuh-agent

```bash
su - editor1 -c 'sudo systemctl restart wazuh-agent'
su - editor1 -c 'sudo systemctl status wazuh-agent --no-pager'
```

### 5.4. Positive: агент жив

```bash
systemctl is-active wazuh-agent
tail -n 30 /var/ossec/logs/ossec.log
```

### 5.5. Negative tests (editor)

```bash
su - editor1 -c 'sudo bash'                         # DENY
su - editor1 -c 'sudo vim /var/ossec/etc/ossec.conf' # DENY
su - editor1 -c 'sudoedit /etc/sudoers'              # DENY
su - editor1 -c 'sudoedit /etc/shadow'               # DENY
su - editor1 -c 'sudo systemctl restart sshd'        # DENY
su - editor1 -c 'sudo systemctl restart auditd'      # DENY
```

```bash
ausearch -k wazuh_conf -ts recent | tail
grep editor1 /var/log/sudo.log | tail
```

---

## 6. РОЛЬ timeditor — временный NOPASSWD

```bash
# от svcsecadmin:
/usr/local/sbin/timeditor-grant editor1
cat /var/lib/rbac-timers/editor1
# user=editor1
# expire_epoch=...

su - editor1 -c 'sudo -n -l'   # NOPASSWD для sudoedit/restart
```

Продление — только повторный `timeditor-grant` админом.  
По истечении 8 часов timer вызывает `timeditor-expire`:

```bash
# принудительная проверка:
sed -i "s/^expire_epoch=.*/expire_epoch=$(date +%s)/" /var/lib/rbac-timers/editor1
# подождать tick или:
systemctl start timeditor-expire.service
id editor1 | grep timeditor || echo "timeditor removed OK"
ausearch -k timeditor_expire -ts recent || grep timeditor /var/log/rbac/timeditor-expire.log
```

---

## 7. Критерии приёмки примера Wazuh

Заполните акт:

```
ОС: _______________  Версия агента: _______________
Manager address: _______________

[ ] пакет установлен штатно (rpm -q / dpkg -l wazuh-agent)
[ ] /var/ossec существует, unit enabled+active
[ ] ossec.conf содержит верный <address>
[ ] ossec.log без блокирующих ошибок прав
[ ] РЕД ОС: нет критичных AVC | Astra: нет блокирующих PARSEC denials
[ ] svcsec только upload (не ставил пакет)
[ ] poinstall DENY dnf/apt/systemctl и записи в /var/ossec
[ ] editor sudoedit OK; DENY bash/sudoers/shadow/чужие unit’ы
[ ] SSH svcsecadmin DENY
[ ] audit: artifact_approve, pkg_mgr, wazuh_conf, svcsec_super найдены

Вывод: агент работает, роли не смешаны.
```

Команды сбора:

```bash
rpm -q wazuh-agent 2>/dev/null || dpkg -l wazuh-agent
systemctl status wazuh-agent --no-pager
grep -A2 '<server>' /var/ossec/etc/ossec.conf
./tests/matrix-tests.sh --with-wazuh
```

---

## 8. Контраст ещё раз (чтобы не «упростить» через poinstall)

| Шаг | Self-contained app | Wazuh Agent |
|-----|--------------------|-------------|
| Upload | svcsec → staging | svcsec → staging |
| Approve | svcsecadmin | svcsecadmin |
| Install | **poinstall** → `/opt/apps` | **svcsecadmin** → dnf/apt → `/var/ossec` |
| Start | бинарь app / свой supervisor | **systemd** wazuh-agent |
| Config | sudoedit `/etc/opt/apps/...` | sudoedit `/var/ossec/etc/ossec.conf` |

Так пример остаётся реалистичным: Wazuh работает как системная служба, а
модель ролей не размывается ради «всё через poinstall».

---

## 9. Отличия Manager (кратко)

Если нужен Wazuh Manager на той же схеме ролей:

1. В staging кладёте `wazuh-manager-*.rpm|deb`.  
2. svcsecadmin ставит пакет и `systemctl enable --now wazuh-manager`.  
3. В sudoers editor заводите отдельный `Cmnd_Alias` на
   `restart|status wazuh-manager` и расширяете whitelist conf/rules **явно**.  
4. Firewall входящих 1514/1515 — только svcsecadmin.  
5. poinstall по-прежнему не ставит manager.
