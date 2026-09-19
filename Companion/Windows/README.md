# Companion — Windows

## Требования
- Python 3.10+ (https://www.python.org/downloads/)
- PowerShell или CMD

## Запуск
```bat
py Companion\aiagenthub_companion.py --root %USERPROFILE%\Projects --allow-shell --host 127.0.0.1
```

## Автозапуск
1. Создайте ярлык с командой выше в `shell:startup`
2. Или создайте задачу в Task Scheduler → Trigger: At log on → Action: Start a program

Брандмауэр Windows спросит разрешение — разрешите частную сеть.
