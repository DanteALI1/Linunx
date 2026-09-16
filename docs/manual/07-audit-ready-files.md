# Готовые правила auditd (один файл на ОС)

Копируете файл целиком в `/etc/audit/rules.d/` — у каждого правила сверху
краткий комментарий «что делает» (без разбора ключей).

| ОС | Файл | УЗ установки |
|----|------|--------------|
| РЕД ОС 8 | [`redos8/audit/READY-all-rules.rules`](../../redos8/audit/READY-all-rules.rules) | `root` / `svcsecadmin` |
| Astra SE 1.8 | [`astra18/audit/READY-all-rules.rules`](../../astra18/audit/READY-all-rules.rules) | `root` / `svcsecadmin` |

```bash
# РЕД ОС:
cp redos8/audit/READY-all-rules.rules /etc/audit/rules.d/50-rbac-all.rules
augenrules --load
systemctl enable --now auditd

# Astra:
cp astra18/audit/READY-all-rules.rules /etc/audit/rules.d/50-rbac-all.rules
# + audisp-parsec.conf при необходимости
augenrules --load
systemctl enable --now auditd
```

После отладки в конце файла раскомментируйте `-e 2`.

Подробный каталог ключей (если нужен разбор ausearch):  
[`06-auditd-rules-catalog.md`](06-auditd-rules-catalog.md).
