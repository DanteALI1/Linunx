# Пример политики SFTP для staging (документация)
#
# OpenSSH internal-sftp не имеет флага «запрет overwrite».
# Компенсации:
# 1) ChrootDirectory /opt/install + ForceCommand internal-sftp -d /staging
# 2) sticky bit 1770 на staging + ACL только svcsec write
# 3) approve-artifact удаляет файл из staging после копирования в approved
# 4) audit -w /opt/install/staging
# 5) опционально: отдельный read-only NFS/том для approved; staging — tmpfs с квотой
#
# Запрет delete для svcsec (жёсткий): вынести upload на отдельный «dropbox»
# пользователя с ACL default:user::rw,group::r-x и без delete через
# filesystem permissions + процесс-approve от admin.
