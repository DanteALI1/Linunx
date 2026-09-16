# Playbook / Runbook: установка Wazuh Agent

Используйте **только** ветку своей ОС. Роли согласованы с `docs/03-wazuh-e2e.md`.

---

## A) РЕД ОС 8

### Подготовка (один раз)

```bash
./redos8/scripts/apply-redos.sh
# SELinux enforcing + restorecon — docs/01-redos8-guide.md
```

### Поставка (svcsec)

```bash
sha256sum wazuh-agent-*.rpm | tee wazuh-agent-<ver>.rpm.sha256
sftp svcsec@<host>
# put files into /staging/
```

### Установка (svcsec → super → svcsecadmin)

```bash
super
approve-artifact /opt/install/staging/wazuh-agent-<ver>.rpm
install-wazuh-agent-redos <MANAGER_IP_OR_DNS>
systemctl status wazuh-agent --no-pager
tail -n 50 /var/ossec/logs/ossec.log
ausearch -k artifact_approve -ts recent
ausearch -k pkg_mgr -ts recent
```

### Конфиг (editor)

```bash
sudoedit /var/ossec/etc/ossec.conf
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent
```

### Helpers (poinstall) — опционально

```bash
# положить install-wazuh-helpers.sh в approved от svcsecadmin
sudo /opt/install/approved/install-wazuh-helpers.sh
```

### Negative (обязательно)

```bash
# как poinstaller:
sudo dnf install ./wazuh-agent.rpm     # DENY
sudo systemctl restart wazuh-agent     # DENY
# как editor1:
sudo bash                              # DENY
sudoedit /etc/shadow                   # DENY
```

---

## B) Astra Linux SE 1.8

### Подготовка

```bash
./astra18/scripts/apply-astra.sh
# PARSEC checklist — astra18/parsec/CHECKLIST.md
```

### Поставка (svcsec)

```bash
sha256sum wazuh-agent-*.deb | tee wazuh-agent-<ver>.deb.sha256
sftp svcsec@<host>   # → /staging/
```

### Установка (svcsecadmin)

```bash
super
approve-artifact /opt/install/staging/wazuh-agent-<ver>.deb
install-wazuh-agent-astra <MANAGER_IP_OR_DNS>
# применить метки PARSEC к /var/ossec по чеклисту
systemctl status wazuh-agent --no-pager
```

### Конфиг (editor)

```bash
sudoedit /var/ossec/etc/ossec.conf
sudo systemctl restart wazuh-agent
```

### Negative

```bash
sudo apt-get install wazuh-agent   # DENY as poinstall
sudo systemctl restart wazuh-agent # DENY as poinstall
sudo bash                          # DENY as editor
```

---

## Приёмка (обе ОС)

См. критерии в `docs/03-wazuh-e2e.md` и `tests/TEST-MATRIX.md`.

```bash
./tests/matrix-tests.sh --with-wazuh
```
