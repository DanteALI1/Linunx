# SELinux checklist и рекомендуемые действия — РЕД ОС 8
# Режим: enforcing (обязательно для приёмки)

## 1. Базовая проверка
# getenforce                    → Enforcing
# sestatus
# cat /etc/selinux/config       → SELINUX=enforcing

## 2. Контексты каталогов RBAC
# semanage fcontext -a -t admin_home_t "/opt/install(/.*)?"   # уточните тип под политику
# Рекомендуемые типы (адаптируйте под refpolicy RedOS):
#   /opt/install/staging  → public_content_rw_t или кастомный rbac_staging_t
#   /opt/install/approved → bin_t / usr_t для исполняемых скриптов после approve
#   /opt/apps             → usr_t / lib_t для бинарей приложений
#   /var/opt/apps         → var_t / var_lib_t, без exec_t

## Пример (после создания кастомного модуля или использования штатных типов):
# semanage fcontext -a -t var_t "/var/opt/apps(/.*)?"
# semanage fcontext -a -t usr_t "/opt/apps(/.*)?"
# restorecon -Rv /opt/install /opt/apps /var/opt/apps

## 3. Wazuh на SELinux
# Пакет wazuh-agent обычно поставляет/требует контексты.
# После установки:
#   restorecon -Rv /var/ossec
#   systemctl status wazuh-agent
# Проверка AVC:
#   ausearch -m avc -ts recent
#   sealert -a /var/log/audit/audit.log   # если setroubleshoot установлен

## 4. Booleans (только при необходимости, фиксировать в runbook)
# getsebool -a | grep -E 'httpd|fips|deny|exec'
# НЕ отключайте SELinux ради Wazuh. Исправляйте контексты/модуль.

## 5. Генерация локального модуля при легитимных AVC (svcsecadmin)
# ausearch -m avc -ts recent --raw | audit2allow -M rbac_wazuh_local
# semodule -i rbac_wazuh_local.pp
# Документировать каждое allow-правило.

## 6. Запрет для poinstall/editor
# Политика должна запрещать:
#   - запись в /etc/systemd, /usr, /boot
#   - загрузку модулей ядра
#   - setenforce 0 (audit + MAC; только svcsecadmin console emergency)

## 7. Чеклист приёмки
# [ ] getenforce = Enforcing
# [ ] нет критичных AVC для wazuh-agent в штатном режиме
# [ ] restorecon выполнен на /var/ossec /opt/apps /opt/install
# [ ] fapolicyd (опц.) не блокирует /opt/apps и /var/ossec/bin легитимно
