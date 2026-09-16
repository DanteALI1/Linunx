# Матрица тестов pass/deny + ausearch

## Обозначения

- **PASS** — действие должно завершиться успехом
- **DENY** — отказ sudo / DAC / MAC / SSH

## Таблица

| ID | Роль | Действие | Ожидание | ausearch / проверка |
|----|------|----------|----------|---------------------|
| T01 | svcsec | SFTP put в `/staging` | PASS | `-k install_staging` |
| T02 | svcsec | SSH interactive shell (если ForceCommand) | DENY | sshd log |
| T03 | svcsec | `super` → svcsecadmin session | PASS | `-k svcsec_super` |
| T04 | any | `ssh svcsecadmin@host` | DENY | sshd |
| T05 | svcsecadmin | `approve-artifact` | PASS | `-k artifact_approve` |
| T06 | svcsecadmin | dnf/apt install wazuh-agent | PASS | `-k pkg_mgr` |
| T07 | svcsecadmin | `systemctl enable --now wazuh-agent` | PASS | `-k systemctl` |
| T08 | poinstall | helpers → `/opt/apps/wazuh-helpers` | PASS | `-k apps_write` |
| T09 | poinstall | `sudo dnf/apt install wazuh-agent` | DENY | sudo.log + `-k sudo_exec` |
| T10 | poinstall | `sudo systemctl restart wazuh-agent` | DENY | sudo.log |
| T11 | poinstall | write `/var/ossec/etc` | DENY | DAC/MAC + `-k wazuh_conf` |
| T12 | editor | `sudoedit ossec.conf` | PASS | `-k wazuh_conf` / sudo iolog |
| T13 | editor | `systemctl restart wazuh-agent` | PASS* | `-k systemctl` |
| T14 | editor | `sudo bash` | DENY | sudo.log |
| T15 | editor | `sudoedit /etc/sudoers` | DENY | sudo.log |
| T16 | editor | `sudoedit /etc/shadow` | DENY | sudo.log |
| T17 | editor | `sudo vim ossec.conf` | DENY | sudo.log |
| T18 | editor | `systemctl restart sshd` | DENY | sudo.log |
| T19 | timeditor | sudoedit NOPASSWD | PASS (в TTL) | sudo.log |
| T20 | — | после 8ч снятие группы | PASS | `-k timeditor_expire` |
| T21 | RedOS | AVC блокирующие wazuh | нет | `ausearch -m avc` |
| T22 | Astra | PARSEC denial блокирующий wazuh | нет | parsec logs |

\* T13 PASS только если включён узкий `WAZUH_AGENT_CTL` (в комплекте включён).

## Автоматизация

```bash
chmod +x tests/matrix-tests.sh
# после установки агента:
./tests/matrix-tests.sh --with-wazuh
```

## Шаблон сбора улик

```bash
ausearch -k artifact_approve -ts today
ausearch -k pkg_mgr -ts today
ausearch -k wazuh_conf -ts today
ausearch -k svcsec_super -ts today
ausearch -k timeditor_expire -ts today
ausearch -k sudo_exec -ts today | tail -n 50
grep -E 'poinstaller|editor1|svcsec' /var/log/sudo.log | tail -n 50
```
