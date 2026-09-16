# ПРИМЕР: Wazuh — end-to-end

Цель: рабочий **Wazuh Agent** при жёстком разграничении ролей.
По умолчанию — Agent; отличия Manager — в конце.

## Контраст: self-contained vs Wazuh

| | Обычное ПО | Wazuh Agent |
|--|------------|-------------|
| Кто ставит | **poinstall** | **svcsecadmin** |
| Куда | `/opt/apps/<app>` | `/var/ossec` + systemd unit |
| Пакетный менеджер | запрещён | dnf (РЕД ОС) / apt (Astra) |
| Конфиг | sudoedit `/etc/opt/apps/...` | sudoedit `/var/ossec/etc/ossec.conf` |
| Зачем так | вендорский бандл без rpm | штатный агент ОС, корректные пути/unit/MAC |

Попытка «поставить Wazuh через poinstall в /opt/apps» ломает обновления, MAC-контексты и unit’ы — поэтому **не используется**.

## Исходные артефакты (staging)

```
/opt/install/staging/wazuh-agent-<ver>.rpm|deb
/opt/install/staging/wazuh-agent-<ver>.sha256
# опционально:
/opt/install/staging/ossec.conf.template
/opt/install/staging/MANAGER.txt          # IP/DNS, порты 1514/tcp и т.д.
```

---

## РОЛЬ A — svcsec (поставка)

1. SSH keys → host.
2. SFTP (ForceCommand internal-sftp, chroot `/opt/install`):

```bash
sftp svcsec@host
sftp> put wazuh-agent-4.x.x.rpm /staging/
sftp> put wazuh-agent-4.x.x.rpm.sha256 /staging/
```

3. Запрещено: shell, overwrite чужих политикой sticky/ACL, выход из chroot, install.
4. Переход к админу:

```bash
# на хосте, сессия svcsec (если разрешён ограниченный shell локально)
# либо с jump-хоста через отдельный канал — по политике;
# штатно UX:
super
# = sudo -u svcsecadmin /usr/local/sbin/svcsec-super
```

**Negative:** `ssh svcsecadmin@host` → deny.  
**Negative:** svcsec не может `dnf/apt install`.

---

## РОЛЬ B — svcsecadmin (approve + install + start)

### РЕД ОС 8

```bash
/usr/local/sbin/approve-artifact /opt/install/staging/wazuh-agent-4.x.x.rpm
/usr/local/sbin/install-wazuh-agent-redos 10.0.0.10
# внутри: dnf install, sed <address>, restorecon, systemctl enable --now
systemctl is-active wazuh-agent
ausearch -k pkg_mgr -ts recent
ausearch -k artifact_approve -ts recent
```

### Astra SE 1.8

```bash
/usr/local/sbin/approve-artifact /opt/install/staging/wazuh-agent-4.x.x.deb
/usr/local/sbin/install-wazuh-agent-astra 10.0.0.10
# метки PARSEC — по astra18/parsec/CHECKLIST.md
systemctl is-active wazuh-agent
```

**Фиксация в audit:** keys `artifact_approve`, `pkg_mgr`, `systemctl`, `wazuh_conf`.

**Не оставлять** svcsec/poinstall прав на общий `systemctl`/`dnf`/`apt`.

---

## РОЛЬ C — poinstall (вспомогательная)

Допустимо:

```bash
# от poinstaller с sudo whitelist:
sudo /opt/install/approved/install-wazuh-helpers.sh
# → /opt/apps/wazuh-helpers/{bin,lib}
```

Пример содержимого helpers: offline collectors, шаблоны документации, **не** агент.

**Negative tests (обязательны):**

```bash
sudo dnf install wazuh-agent     # DENY (РЕД ОС)
sudo apt-get install wazuh-agent # DENY (Astra)
sudo systemctl restart wazuh-agent  # DENY
sudo touch /var/ossec/etc/x      # DENY (нет прав / нет sudo)
```

---

## РОЛЬ D — editor

```bash
sudoedit /var/ossec/etc/ossec.conf
# изменить параметр (например интервал или комментарий + проверка address)
sudo systemctl restart wazuh-agent   # только узкий Cmnd_Alias
sudo systemctl status wazuh-agent
```

**Positive:** агент active после правки; в логах нет permission errors.  
**Negative:**

```bash
sudo bash                    # DENY
sudoedit /etc/sudoers        # DENY
sudoedit /etc/shadow         # DENY
sudo systemctl restart sshd  # DENY
sudo vim /var/ossec/etc/ossec.conf  # DENY (только sudoedit)
```

---

## РОЛЬ E — timeditor

```bash
# svcsecadmin:
/usr/local/sbin/timeditor-grant editor1
# editor1 в группе timeditor → NOPASSWD sudoedit ossec.conf
# через 8ч: timeditor-expire.timer → gpasswd -d; key=timeditor_expire
```

Продление — только `timeditor-grant` (admin-wrapper).

---

## Критерии «Wazuh работает»

1. Пакет штатно в `/var/ossec`.
2. `systemctl is-enabled wazuh-agent` → enabled; `is-active` → active.
3. В `ossec.conf` корректный `<address>`.
4. `/var/ossec/logs/ossec.log` — нормальный старт (нет блокирующих ошибок прав).
5. РЕД ОС: нет критичных AVC; Astra: нет блокирующих PARSEC denials.
6. svcsec не ставил пакет; poinstall без прав админа ОС; editor без root-shell.

### Проверочные команды

```bash
rpm -q wazuh-agent 2>/dev/null || dpkg -l wazuh-agent
systemctl status wazuh-agent --no-pager
grep -A2 '<server>' /var/ossec/etc/ossec.conf
tail -n 50 /var/ossec/logs/ossec.log
# RedOS:
ausearch -m avc -ts recent | grep -i wazuh || echo "no wazuh AVC"
```

---

## Результат примера (шаблон акта)

```
Дата:
ОС: РЕД ОС 8 | Astra SE 1.8
Версия wazuh-agent:
Manager: <address>
Роли проверены:
  [x] svcsec upload only staging
  [x] svcsecadmin approve+install+start
  [x] poinstall DENY dnf/apt/systemctl;/var/ossec
  [x] editor sudoedit ossec.conf + narrow restart OK
  [x] editor DENY bash/sudoers/shadow
  [x] SSH svcsecadmin DENY
  [x] audit keys present (artifact_approve, pkg_mgr, wazuh_conf)
Агент: active=yes
MAC: OK
Вывод: роли не смешаны, агент работает.
```

---

## Отличия Wazuh Manager

| Тема | Agent | Manager |
|------|-------|---------|
| Пакет | wazuh-agent | wazuh-manager (+ опц. indexer/dashboard отдельно) |
| Unit | wazuh-agent | wazuh-manager |
| sudoedit | ossec.conf (+ client.keys редко) | ossec.conf, правила decoders/rules — **расширять whitelist явно** |
| Порты | исходящие на manager | входящие 1514/1515 и API — firewall **только svcsecadmin** |
| poinstall | helpers | то же; **не** ставит manager |
| restart alias | `restart wazuh-agent` | `restart wazuh-manager` (отдельный Cmnd_Alias) |

Схема ролей **та же**: upload → svcsecadmin install/start → editor sudoedit.
