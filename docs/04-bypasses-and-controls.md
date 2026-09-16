# Известные обходы и контрмеры

Aliases shell **не** считаются контролем. Ниже — реальные векторы обхода DAC/sudo и контрмеры.

| # | Обход / риск | Контрмера |
|---|--------------|-----------|
| 1 | `sudo vim/nano` → `:!bash` shell-escape | Запрет vim/nano в sudoers; **только sudoedit**; Defaults `NOEXEC` где применимо |
| 2 | `sudo less/man/more` → `!sh` | Не включать pager’ы в sudoers; NOEXEC |
| 3 | `sudo systemctl edit` / `systemctl --user` | Не давать общий systemctl; только узкий Cmnd_Alias `restart/status wazuh-agent` |
| 4 | Запись в `~/.config/systemd/user` + linger | MAC + запрет linger для poinstall/editor; audit на systemd |
| 5 | `LD_PRELOAD` / `LD_LIBRARY_PATH` через sudo | `Defaults env_reset`; не сохранять LD_*; SELinux/PARSEC |
| 6 | SFTP overwrite артефакта после hash | Sticky на staging; approve копирует и **удаляет** staging; подпись + быстрый approve |
| 7 | Подмена бинаря в `/opt/apps` → sudo EXEC | sudoers whitelist конкретных путей; fapolicyd (РЕД ОС); MAC exec; hash в approved |
| 8 | `poinstall` пишет unit в `/etc/systemd` | DAC root-only + audit watch + MAC deny + отсутствие в sudoers |
| 9 | Чтение `/etc/shadow` / sudoers | DAC 0; MAC; audit `-w`; группы без доступа |
| 10 | SSH на svcsecadmin | `DenyUsers svcsecadmin`; ключи не выдавать; `passwd -l` опционально |
| 11 | `svcsec` ForceCommand обход через `ssh host command` | Match User ForceCommand internal-sftp; PermitTTY no |
| 12 | Симлинк в sudoedit whitelist на `/etc/shadow` | sudoedit проверяет конечный путь; доп. `Defaults sudoedit_follow=off` (версия sudo); не давать write на dir с symlink injection; SELinux |
| 13 | `timeditor` после TTL через кэш групп | timer 15м; `newgrp`/re-login; при необходимости `systemd --user` kill; audit expire |
| 14 | `noexec` на `/` «для безопасности» | **Запрещено**; ломает ОС и Wazuh; использовать точечный noexec на data/staging |
| 15 | Установка Wazuh в `/opt/apps` poinstall | Политика запрещает; только svcsecadmin rpm/deb → `/var/ossec` |
| 16 | `chmod +s` свои бинарники в `/opt/apps` | nosuid на `/opt/apps` mount; MAC; audit chmod/setxattr |
| 17 | Отключение SELinux `setenforce 0` | Только console root/svcsecadmin; audit; AIDE/мониторинг `/etc/selinux/config` |
| 18 | Отключение PARSEC / понижение меток | Только svcsecadmin; audit `parsec_admin`; организационный контроль |
| 19 | `sudo -u wazuh bash` при ошибочном ALL | Не выдавать runas на служебные УЗ; явный whitelist |
| 20 | Копирование `ossec.conf` с world-writable | После install ACL 0640 root:wazuh; editor только sudoedit |

## Принцип защиты в глубину

```
SSH/PAM → DAC/ACL → sudoers (NOEXEC, sudoedit) → MAC (SELinux|PARSEC) → auditd → (fapolicyd)
```

Любой слой может дать сбой — остальные должны держать модель ролей.
