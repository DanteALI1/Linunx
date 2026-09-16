# PARSEC (МРД/МКЦ) — чеклист и ориентиры для Astra Linux SE 1.8
#
# Точные утилиты и имена уровней зависят от профиля СЗИ и версии ядра PARSEC.
# Ниже — операционная схема, согласованная с ролями RBAC. Перед продом —
# сверить с «Руководством администратора» Astra SE 1.8 вашей сборки.

## 1. Режим MAC
# Убедиться, что мандатный контроль включён (MIC/MAC), не permissive-аналог.
# Типовые проверки (имена команд могут отличаться):
#   astra-modeswitch status
#   pdp-ls -d /
#   cat /proc/self/attr/current   # при поддержке

## 2. Метки каталогов RBAC
# Принцип: staging/approved/apps получают метки, согласованные с уровнем
# процессов svcsec/poinstall; секреты ОС и /etc/parsec — выше/вне доступа.
#
# Примерная схема уровней (иллюстрация — ЗАМЕНИТЕ на принятые в орг. политике):
#   svcsec / staging     — уровень, достаточный для записи файлов поставки
#   poinstall /opt/apps  — уровень прикладного контура
#   /var/ossec           — уровень служб мониторинга (обычно системный)
#   /etc/shadow, sudoers — недоступны poinstall/editor по МРД

## 3. Назначение меток (выполняет ТОЛЬКО svcsecadmin)
# pdpl-user -l <level> svcsec
# pdpl-user -l <level> poinstaller
# # метки файлов:
# # setfilelev / pdpl-file — по документации вашей версии
# restore/переустановка меток после apt install wazuh-agent

## 4. Wazuh и PARSEC
# После apt install wazuh-agent:
#   - процессы wazuh-* должны иметь метки, разрешающие чтение ossec.conf,
#     запись логов в /var/ossec/logs, сеть к manager (1514/tcp и т.д.)
#   - editor меняет conf через sudoedit: временный файл на уровне root/админа,
#     затем атомарная замена — убедиться, что итоговый файл сохраняет нужную метку
#   - при denial: журнал PARSEC + ausearch; не отключать MAC

## 5. audisp-parsec
# systemctl status auditd
# Проверить active=yes в plugins.d/audisp-parsec.conf
# journalctl / логи PARSEC на предмет denials при старте wazuh-agent

## 6. Чеклист приёмки
# [ ] MAC/MIC включены согласно профилю СЗИ
# [ ] нет блокирующих PARSEC denials для штатного wazuh-agent
# [ ] svcsec/poinstall/editor не читают shadow/sudoers по мандату
# [ ] метки /var/ossec корректны после установки пакета
# [ ] audisp-parsec active
