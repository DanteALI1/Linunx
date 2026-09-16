# Справочник правил auditd: ключ → назначение

Документ описывает **все правила из комплекта** и **расширенный набор из реальных
практик** (CIS Benchmark, STIG/RHEL, PCI-DSS-ориентиры, hardening РЕД ОС/RHEL-клонов,
Astra + PARSEC, контейнеры, supply-chain).

Применение правил — **только из-под УЗ `root` или `svcsecadmin`** (консоль).

```bash
# УЗ: svcsecadmin (или root на bootstrap)
install -m 0640 <file> /etc/audit/rules.d/
augenrules --load
auditctl -l
```

Синтаксис кратко:
- `-w PATH -p rwxa -k KEY` — watch файла/каталога (r/w/x/a=attr)
- `-a always,exit -F arch=b64|b32 -S syscall ... -F key=KEY` — syscall
- `-a always,exit -F path=/bin/foo -F perm=x -F auid>=1000 -F auid!=unset -k KEY`
- `-e 2` — замок конфигурации audit до reboot (ставить **последним** после отладки)

Для x86_64 почти всегда дублируют **b64 и b32** (32-bit compat).

Поиск: `ausearch -k KEY -ts today` · `aureport -f` · `ausearch -m USER_AUTH`.

---

## 0. Служебные / базовые (всегда первыми)

| Правило | Ключ | Для чего |
|---------|------|----------|
| `-D` | — | Очистить предыдущие правила перед загрузкой набора (осторожно в rules.d — обычно делает augenrules) |
| `-b 8192` (или 8192–65536) | — | Размер backlog буфера ядра; защита от потери событий под нагрузкой |
| `-f 1` | — | Failure flag: 0=silent, 1=printk, 2=panic при сбое audit |
| `-r 0` | — | Rate limit сообщений (0=без лимита; на шумных хостах ставят >0) |
| `--backlog_wait_time 60000` | — | Ожидание при переполнении backlog |
| `-e 1` | — | Включить audit (enabled) |
| `-e 2` | — | **Immutable**: нельзя менять правила до reboot — после приёмки |

---

## 1. Правила комплекта RBAC (обязательные для этой модели)

### 1.1. Exec критичных бинарей

| Правило (идея) | key | Для чего |
|----------------|-----|----------|
| execve `/usr/bin/dnf`,`yum`,`rpm` | `pkg_mgr` | Кто ставил/снимал пакеты (РЕД ОС); поймает обход poinstall |
| execve `/usr/bin/apt`,`apt-get`,`dpkg` | `pkg_mgr` | То же на Astra |
| execve `/usr/bin/systemctl` | `systemctl` | Управление службами (Wazuh start/restart и чужие unit’ы) |
| execve `/usr/sbin/visudo` | `sudoers_change` | Попытка править sudoers интерактивно |
| execve `/usr/local/sbin/svcsec-super` | `svcsec_super` | Факт перехода svcsec→svcsecadmin |
| execve `/usr/local/sbin/approve-artifact` | `artifact_approve` | Approve staging→approved |
| execve `/usr/local/sbin/timeditor-grant` | `timeditor_grant` | Выдача временной роли |
| execve `/usr/local/sbin/timeditor-expire` | `timeditor_expire` | Снятие TTL |
| execve `/usr/sbin/semanage`,`setsebool` | `selinux_admin` | Изменение SELinux политики/boolean (РЕД ОС) |
| execve `/usr/sbin/pdpl-user`,`usercaps`,`pdp-ls` | `parsec_admin` | Мандатные операции PARSEC (Astra) |
| execve `/usr/bin/sudo` | `sudo_exec` | Все запуски sudo (дополнение к sudo.log) |
| execve `/var/ossec/bin/wazuh-control` | `wazuh_control` | Ручное управление агентом в обход systemctl |

### 1.2. Watch критичных путей RBAC / ОС

| Путь | perm | key | Для чего |
|------|------|-----|----------|
| `/etc/sudoers`, `/etc/sudoers.d` | wa | `sudoers_change` | Изменение делегирования привилегий |
| `/etc/shadow`,`/etc/passwd`,`/etc/group` | wa | `identity` | Учётки и парольные хеши |
| `/etc/ssh/sshd_config`, `sshd_config.d` | wa | `sshd_config` | SFTP Match, DenyUsers |
| `/etc/systemd/system`, `/usr/lib/systemd/system` или `/lib/systemd/system` | wa | `systemd_units` | Подмена unit’ов (persistence) |
| `/etc/selinux` | wa | `selinux_config` | Отключение/ослабление SELinux |
| `/etc/parsec`, `/etc/astra` | wa | `parsec_config` / `astra_config` | Политика Astra/PARSEC |
| `/boot` | wa | `boot_integrity` | Ядро, initramfs, grub |
| `/opt/install/staging` | rwa | `install_staging` | Upload/чтение карантина |
| `/opt/install/approved` | rwa | `install_approved` | Проверенные артефакты |
| `/opt/apps` | wa | `apps_write` | Установка self-contained |
| `/var/opt/apps` | wa | `apps_data` | Данные приложений |
| `/var/ossec/etc` | wa | `wazuh_conf` | Правки conf (sudoedit/admin) |
| `/var/ossec/bin` | wa | `wazuh_bin` | Подмена бинарей агента |
| `/var/ossec/logs/ossec.log` | wa | `wazuh_log` | Тампер логов агента |
| `/var/log/sudo.log` | wa | `sudo_log` | Тампер журнала sudo |
| `/var/lib/rbac-timers` | wa | `timeditor_state` | Подделка TTL timeditor |

---

## 2. Классика CIS / STIG / hardening (реальные практики)

Ниже — правила, которые ставят на боевых RHEL/РЕД ОС/Debian-подобных хостах.
Файлы эталона в репо: `common/audit/`, `redos8/audit/`, `astra18/audit/` (расширенные).

### 2.1. Время (time-change)

| Syscall / watch | key | Для чего |
|-----------------|-----|----------|
| `adjtimex`, `settimeofday`, `clock_settime` | `time_change` | Сдвиг часов (сокрытие следов, керберос/TLS) |
| `-w /etc/localtime` | `time_change` | Смена таймзоны |

### 2.2. Идентичность (identity) — расширение

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/passwd` | `identity` | Создание/смена УЗ |
| `/etc/group` | `identity` | Группы (в т.ч. wheel/sudo/timeditor) |
| `/etc/gshadow` | `identity` | Пароли групп |
| `/etc/shadow` | `identity` | Хеши паролей |
| `/etc/security/opasswd` | `identity` | История паролей (pam_pwhistory) |
| `/etc/subuid`, `/etc/subgid` | `identity` | subordinate IDs (rootless podman/user ns) |

### 2.3. Сетевые параметры системы

| Watch / syscall | key | Для чего |
|-----------------|-----|----------|
| `/etc/hosts` | `system_locale` / `network_mod` | Локальный DNS override / подмена |
| `/etc/hostname`, `/etc/machine-info` | `system_locale` | Имя хоста |
| `/etc/issue`, `/etc/issue.net` | `system_locale` | Баннеры |
| `/etc/sysconfig/network*` (RHEL) | `network_mod` | Скрипты сети |
| `/etc/netplan`, `/etc/network` (Debian) | `network_mod` | Сеть Astra/Debian |
| `/etc/resolv.conf`, `/etc/nsswitch.conf` | `network_mod` | DNS/NSS hijack |
| `/etc/hosts.allow`, `/etc/hosts.deny` | `network_mod` | tcpwrappers (если есть) |
| `sethostname`, `setdomainname` | `system_locale` | Смена имени через syscall |

### 2.4. MAC

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/selinux/` | `MAC_policy` | Политика SELinux |
| `/usr/share/selinux/` | `MAC_policy` | Модули политик |
| `/etc/parsec/` | `MAC_policy` | PARSEC |
| `/etc/apparmor*`, `/etc/apparmor.d` | `MAC_policy` | AppArmor (если встречается) |

### 2.5. Вход / сессии / PAM

| Watch | key | Для чего |
|-------|-----|----------|
| `/var/log/lastlog` | `logins` | Последний вход |
| `/var/log/faillock` или `/var/run/faillock` | `logins` | Блокировки pam_faillock |
| `/var/log/tallylog` | `logins` | pam_tally2 (legacy) |
| `/var/log/wtmp`, `/var/run/utmp`, `/var/log/btmp` | `session` | Login accounting / неудачные |
| `/etc/pam.d` | `pam` | Подмена PAM-стека (бэкдор auth) |
| `/etc/security/` | `pam` | faillock.conf, limits, namespace, access.conf |
| `/var/log/secure` или `/var/log/auth.log` | `logins` | Тампер auth-лога (дополнительно) |

### 2.6. Неуспешный доступ к файлам (EACCES/EPERM)

| Правило | key | Для чего |
|---------|-----|----------|
| `creat,open,openat,openat2,truncate,ftruncate` + `exit=-EACCES` | `access` | Разведка/перебор чужих файлов |
| то же + `exit=-EPERM` | `access` | Отказы по permissions |

На шумных серверах фильтруют `-F auid>=1000 -F auid!=unset`.

### 2.7. Изменение DAC (chmod/chown/xattr)

| Syscall | key | Для чего |
|---------|-----|----------|
| `chmod`, `fchmod`, `fchmodat` | `perm_mod` | Смена mode (выдача +x/setuid) |
| `chown`, `fchown`, `lchown`, `fchownat` | `perm_mod` | Смена владельца |
| `setxattr`, `lsetxattr`, `fsetxattr`, `removexattr`… | `perm_mod` | ACL/capabilities в xattr, security.* |

### 2.8. Монтирование

| Syscall / watch | key | Для чего |
|-----------------|-----|----------|
| `mount`, `umount`, `umount2` | `mounts` | Подмена FS, bind-mount обходы chroot |
| `/usr/bin/mount`, `/usr/bin/umount` | `mounts` | Userland mount |
| `/etc/fstab` | `mounts` | Постоянные mount-опции (noexec и т.д.) |

### 2.9. Удаление файлов

| Syscall | key | Для чего |
|---------|-----|----------|
| `unlink`, `unlinkat`, `rename`, `renameat`, `renameat2` | `delete` | Уничтожение улик / подмена через rename |
| Часто с `-F dir=/var/log` и т.п. | `delete` | Точечно по критичным каталогам |

### 2.10. Загрузка модулей ядра

| Syscall / path | key | Для чего |
|----------------|-----|----------|
| `init_module`, `finit_module`, `delete_module` | `modules` | Rootkit/драйвер |
| `/usr/bin/kmod`, `insmod`, `rmmod`, `modprobe` | `modules` | Userland загрузка |
| `/etc/modprobe.d` | `modules` | blacklist/install tricks |

### 2.11. Привилегированные команды (setuid/setgid)

Практика STIG: сгенерировать список и повесить `-F path=... -F perm=x`:

```bash
# УЗ: svcsecadmin
find /usr -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null
```

| key | Для чего |
|-----|----------|
| `privileged` | Запуск suid/sgid (su, passwd, newuidmap, mount…) |

### 2.12. sudo / su / повышение

| Watch / path | key | Для чего |
|--------------|-----|----------|
| `/etc/sudoers`, `/etc/sudoers.d` | `scope` / `sudoers_change` | CIS key name `scope` |
| execve `/usr/bin/sudo`, `/usr/bin/su` | `priv_esc` | Повышение привилегий |
| execve `/usr/bin/newgrp`, `sg` | `priv_esc` | Смена группы |
| `/var/log/sudo.log`, I/O dir | `sudo_log` | Тампер |

### 2.13. Планировщики

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/cron.d`, `cron.daily`, `cron.hourly`, `cron.weekly`, `cron.monthly` | `cron` | Persistence |
| `/etc/crontab`, `/var/spool/cron`, `/var/spool/cron/crontabs` | `cron` | Пользовательские crontab |
| `/etc/anacrontab` | `cron` | anacron |
| `/etc/at.allow`, `/etc/at.deny`, `/var/spool/at` | `cron` | at-jobs |

### 2.14. Пользовательские утилиты учёток

| path execve | key | Для чего |
|-------------|-----|----------|
| `useradd`,`userdel`,`usermod`,`groupadd`,`groupdel`,`groupmod` | `user_mod` | Управление УЗ вне штатного процесса |
| `passwd`,`chage`,`chpasswd` | `user_mod` | Смена паролей/старения |
| `gpasswd` | `user_mod` | В т.ч. снятие timeditor |

### 2.15. Конфиг самого audit

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/audit/` | `audit_cfg` | Изменение правил/auditd.conf |
| `/etc/libaudit.conf` | `audit_cfg` | |
| `/var/log/audit/` | `audit_log` | Тампер журналов audit |
| execve `auditctl`,`augenrules` | `audit_tools` | Кто менял runtime rules |

### 2.16. SSH и ключи

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/ssh/sshd_config*` | `sshd_config` | Политика доступа |
| `/etc/ssh/ssh_host_*` | `ssh_keys` | Host keys |
| `/root/.ssh` | `ssh_keys` | Ключи root |
| `/home/*/.ssh/authorized_keys` (осторожно, шум) | `ssh_keys` | Добавление бэкдор-ключей |
| Для svcsec точечно: `/home/svcsec/.ssh` | `ssh_keys` | Ключ поставщика |

### 2.17. Крипто / PKI / секреты

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/pki`, `/etc/ssl`, `/etc/ipa` | `crypto_policy` | Корневые/TLS материалы |
| `/etc/crypto-policies` (RHEL) | `crypto_policy` | Системная crypto policy |
| `/etc/openldap`, `/etc/krb5*` | `auth_infra` | Каталог/Kerberos |
| `/etc/vault`, `/etc/credstore` (если есть) | `secrets` | Секреты приложений |
| `/root` (часто `-p wa` слишком шумно — лучше точечно) | `root_home` | |

### 2.18. Firewall / сеть admin

| path / watch | key | Для чего |
|--------------|-----|----------|
| `firewall-cmd`, `firewalld` conf | `firewall` | РЕД ОС |
| `iptables`,`ip6tables`,`nft`,`nftables` | `firewall` | |
| `/etc/nftables*`, `/etc/iptables` | `firewall` | |
| `ufw` (если есть) | `firewall` | |
| execve `ip`, `sshd` restart already via systemctl | `network_admin` | |

### 2.19. systemd / unit persistence (расширение)

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/systemd/system` | `systemd_units` | |
| `/usr/lib/systemd/system`, `/lib/systemd/system` | `systemd_units` | |
| `/etc/systemd/user`, `/etc/systemd/system/*.wants` | `systemd_units` | |
| `/var/lib/systemd` | `systemd_state` | enable links и т.п. |
| `/etc/init.d` (sysv remnant) | `systemd_units` | |

### 2.20. Динамический линкер / preload

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/ld.so.conf`, `/etc/ld.so.conf.d` | `linker` | Подмена путей библиотек |
| `/etc/ld.so.preload` | `linker` | Классический LD_PRELOAD persistence |
| `/etc/ld.so.cache` | `linker` | |

### 2.21. Специальные syscall’ы атак (современные практики)

| Syscall | key | Для чего |
|---------|-----|----------|
| `ptrace` | `ptrace` | Инъекция/кража памяти процессов |
| `personality` | `perm_mod` / `evasion` | Обход некоторых защит |
| `bpf` | `bpf` | eBPF rootkit / скрытие |
| `process_vm_readv`, `process_vm_writev` | `proc_mem` | Чтение/запись памяти чужого процесса |
| `userfaultfd` | `proc_mem` | Техники abuse |
| `perf_event_open` | `perf` | Иногда в threat hunting |
| `reboot`, `kexec_load`, `kexec_file_load` | `reboot` | Внезапная перезагрузка/подмена ядра |

### 2.22. Контейнеры / виртуализация (если применимо)

| Watch / path | key | Для чего |
|--------------|-----|----------|
| `/var/lib/docker`, `/etc/docker` | `containers` | Docker |
| `/var/lib/containers`, `/etc/containers` | `containers` | Podman |
| `/usr/bin/docker`,`podman`,`nerdctl`,`crictl` | `containers` | Runtime CLI |
| `/var/run/docker.sock`, `podman.sock` | `containers` | Socket = root-эквивалент |
| `/etc/cni`, `/etc/kubernetes` | `k8s` | Если control-plane |

### 2.23. FIM-смежные каталоги приложений (практика SOC)

| Watch | key | Для чего |
|-------|-----|----------|
| `/usr/local/sbin`, `/usr/local/bin` | `local_bin` | Наши wrapper’ы RBAC |
| `/opt` (широко — шумно) | `opt_write` | Лучше точечно как в RBAC |
| `/etc/ld.so.preload` уже выше | | |
| `/etc/rc.local` | `startup` | Legacy persistence |

### 2.24. СЪёмные носители / USB (часто на защищённых контурах)

| Watch / key | Для чего |
|-------------|----------|
| `-w /var/run/usb` / udev rules | Подключение USB |
| execve `udisksctl` key=`usb_mount` | Монтирование пользователем |
| `-a ... -F arch=... -S mount -F auid>=1000` уже в mounts | |

### 2.25. Wazuh / SIEM agent (расширение комплекта)

| Watch / path | key | Для чего |
|--------------|-----|----------|
| `/var/ossec/etc` | `wazuh_conf` | |
| `/var/ossec/bin` | `wazuh_bin` | |
| `/var/ossec/agentless`, `/var/ossec/etc/shared` | `wazuh_shared` | Shared config от manager |
| `/var/ossec/queue` | `wazuh_queue` | Очереди (тампер/DoS) |
| `/var/ossec/var/run` | `wazuh_run` | pid/state |
| `/etc/ossec*` если есть | `wazuh_conf` | |
| unit files `wazuh-agent.service` через systemd watch | `systemd_units` | |

### 2.26. fapolicyd / IMA / AIDE (РЕД ОС практики)

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/fapolicyd` | `fapolicyd` | Политика exec |
| `/etc/ima`, `/sys/kernel/security/ima` (ограниченно) | `ima` | Integrity Measurement |
| `/var/lib/aide`, `/etc/aide*` | `aide` | База эталонов |

### 2.27. Почта / печати / прочее enterprise (по необходимости)

| Watch | key | Для чего |
|-------|-----|----------|
| `/etc/postfix`, `/etc/aliases` | `mail` | Relay abuse |
| `/etc/cups` | `print` | |

---

## 3. Ключи комплекта — шпаргалка ausearch

```bash
# УЗ: svcsecadmin
for k in pkg_mgr systemctl sudoers_change identity sshd_config systemd_units \
         selinux_admin parsec_admin selinux_config parsec_config astra_config \
         boot_integrity install_staging install_approved apps_write apps_data \
         wazuh_conf wazuh_bin wazuh_log wazuh_control \
         svcsec_super artifact_approve timeditor_grant timeditor_expire timeditor_state \
         sudo_exec sudo_log \
         time_change access perm_mod mounts delete modules privileged priv_esc \
         cron user_mod audit_cfg audit_log linker ptrace bpf firewall MAC_policy \
         logins session pam crypto_policy ssh_keys local_bin; do
  echo "==== $k ===="
  ausearch -k "$k" -ts today 2>/dev/null | tail -n 3
done
```

---

## 4. Рекомендуемый порядок файлов в `/etc/audit/rules.d/`

| Файл | УЗ, кто кладёт | Содержание |
|------|----------------|------------|
| `00-base.rules` | svcsecadmin | `-b`, `-f`, buffer |
| `10-hardening-*.rules` | svcsecadmin | CIS/STIG практика (time, identity, MAC…) |
| `40-privileged.rules` | svcsecadmin | сгенерённые suid path |
| `50-rbac-*.rules` | svcsecadmin | роли /opt/install, Wazuh |
| `60-local-extras.rules` | svcsecadmin | сайт-специфика |
| `99-finalize.rules` | svcsecadmin | `-e 2` после отладки |

Эталоны в репозитории:
- `common/audit/00-base.rules`
- `common/audit/10-hardening-common.rules`
- `common/audit/10-hardening-syscalls.rules`
- `redos8/audit/50-rbac-redos.rules` (+ `11-hardening-redos.rules`)
- `astra18/audit/50-rbac-astra.rules` (+ `11-hardening-astra.rules`)
- `common/audit/99-finalize.rules.example`

---

## 5. Шум и производительность (практика)

| Проблема | Что делать |
|----------|------------|
| Слишком много `access`/`perm_mod` | Ограничить `-F auid>=1000`, исключить системные демоны |
| Watch на весь `/opt` | Сузить до staging/approved/apps |
| `open` на каждый лог | Не вешать `-p r` на высокочастотные логи без нужды |
| Потеря событий | Увеличить `-b`, диск для `/var/log/audit`, мониторить `aureport --failed` |
| Контейнерный хост | Отдельный профиль, иначе flood от overlay mounts |

---

## 6. Связь с ролями (кто должен «светиться» в каком ключе)

| key | Нормальные УЗ в событиях | Подозрительно |
|-----|--------------------------|---------------|
| `install_staging` | svcsec, svcsecadmin | editor, poinstall write |
| `artifact_approve` | svcsecadmin | кто угодно ещё |
| `pkg_mgr` | svcsecadmin | poinstaller, editor1 |
| `apps_write` | poinstaller, svcsecadmin | svcsec |
| `wazuh_conf` | editor*, svcsecadmin | poinstaller |
| `svcsec_super` | переход от svcsec | частые неожиданные |
| `timeditor_grant` | svcsecadmin | самовыписывание |
| `selinux_admin` / `parsec_admin` | svcsecadmin | все прочие |
| `modules` / `linker` / `bpf` | почти никогда | всегда разбор |
