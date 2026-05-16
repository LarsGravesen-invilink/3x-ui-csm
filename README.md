<img width="914" height="511" alt="Screenshot_2026-05-16-15-30-31-35_99c04817c0de5652397fc8b56c3b3817" src="https://github.com/user-attachments/assets/38b506d0-3d11-4ac0-929c-525812070136" />
<p align="center">
  <img src="https://img.shields.io/badge/version-1.0_(free)-blue?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/platform-Linux-orange?style=for-the-badge&logo=linux&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/shell-bash-121011?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Shell">
  <img src="https://img.shields.io/badge/3x--ui-v2.4%2B-blueviolet?style=for-the-badge" alt="3x-ui">
</p>

<h1 align="center">3X-UI CSM — CLI Subscription Manager</h1>

<p align="center">
  <b>CLI-инструмент для автоматического сбора VPN-ключей с нескольких панелей 3x-UI и формирования единого файла подписки (base64/plain text) с раздачей через Nginx.</b>
</p>

<p align="center">
  <a href="https://t.me/LarsInvilink">
    <img src="https://img.shields.io/badge/Telegram-Support-blue?style=flat-square&logo=telegram" alt="Telegram">
  </a>
</p>

---

## Что это?

**3X-UI CSM** (Client Subscription Manager) — bash-скрипт для VPS, который:

- Подключается к одной или нескольким панелям **3x-UI** по API
- Собирает **VPN-ключи** со всех выбранных инбаундов
- Объединяет их в один файл подписки
- Раздаёт файл через встроенный **Nginx** (HTTP/HTTPS)
- Автоматически обновляет подписку по расписанию через **cron**

Один URL → все серверы → все клиенты.

---

## Возможности

| Функция | Описание |
|---------|----------|
| **Мульти-сервер** | Добавление нескольких панелей 3x-UI с авторизацией |
| **Выбор инбаундов** | Можно выбрать конкретные инбаунды для каждого сервера |
| **Автообновление** | Автообновление: **минуты / часы / дни** на выбор |
| **Домен + SSL** | Поддержка домена с автоматическим Let's Encrypt |
| **Кодирование URL** | Путь к подписке можно закодировать в base64 или декодировать в любой момент |
| **Кодирование файла** | Содержимое подписки: base64 или plain text (можно изменять) |
| **Заголовки подписки** | profile-title, update-interval, support-url, userinfo — каждый включается/выключается отдельно |
| **QR-код** | Генерация QR-кода подписки прямо в терминале |
| **Диагностика** | Проверка доступности URL с авто-восстановлением nginx |
| **Полное удаление** | Удаление всех компонентов с опциональным сохранением файла подписки |

---

## Требования

- **ОС:** Ubuntu 20.04+ / Debian 11+ (или любой Linux с `apt`)
- **Права:** root
- **3x-UI:** версия 2.4.0+ (рекомендуется 2.5.0+)
- **Свободные порты:** 80 (для SSL), 443 (HTTPS) или 8443 (по умолчанию, настраиваемый параметр)

---

## Быстрая установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LarsGravesen-invilink/3x-ui-csm/main/install.sh)
```

Или скачать и запустить вручную:

```bash
curl -fsSL https://raw.githubusercontent.com/LarsGravesen-invilink/3x-ui-csm/main/install.sh -o /tmp/3xcsm-install.sh
chmod +x /tmp/3xcsm-install.sh
sudo bash /tmp/3xcsm-install.sh
```

После установки для запуска меню:

```bash
3xsub
```

---

## Скриншоты

<details>
<summary><b>Главное меню</b></summary>

```
  Серверов: 2 | Ключей: 15 | Авто: ● 59мин

    1)  ➕  Добавить сервер 3x-UI
    2)  📋  Список серверов
    3)  ⏰  Автообновление
    4)  📝  Название подписки
    5)  🔄  Обновить подписку
    6)  📄  Файл подписки

    7)  📊  Обзор подписки
    8)  ℹ   Информация и обновление

    9)  🗑️   Полное удаление
    0)  🚪  Выход

  URL: http://your-ip:8443/sub.txt
```

</details>

<details>
<summary><b>Меню файла подписки</b></summary>

```
  ├─ Путь:                /var/www/3xcsm/sub.txt
  ├─ Размер:              1024 байт
  ├─ Обновлён:            2026-05-15 12:00:00
  ├─ Ключей:              15
  ├─ Кодирование URL:     Выкл
  └─ Кодирование файла:   Вкл (base64)

    1) Редактировать ключи
    2) Показать все ключи
    3) Скопировать URL
    4) Настройки домена и SSL
    5) Кодирование base64
    6) Кодирование URL
    7) Проверить доступность URL
    8) Показать QR-код подписки
```

</details>

---

## Как это работает

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  3x-UI #1    │     │  3x-UI #2    │     │  3x-UI #N    │
│  (сервер 1)  │     │  (сервер 2)  │     │  (сервер N)  │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └────────────┬───────┘────────────────────┘
                    │
            ┌───────▼───────┐
            │   3X-UI CSM   │
            │  │
            └───────┬───────┘
                    │
            ┌───────▼───────┐
            │  Nginx        │
            │  subscribe.txt│──── http://ip:8443/sub.txt
            └───────────────┘
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
    Hiddify     v2rayNG       Happ
```

1. Скрипт авторизуется в каждой панели 3x-UI через API
2. Получает список инбаундов и извлекает VLESS-ключи
3. Формирует файл подписки с заголовками
4. Кодирует в base64 (опционально)
5. Nginx раздаёт файл по HTTP/HTTPS
6. VPN-клиенты обновляют подписку по URL

---

## Структура файлов

```
/opt/3xcsm/
├── 3xcsm.sh           # Основной скрипт
├── config.json         # Конфигурация
├── servers.json        # Список серверов 3x-UI
├── raw_keys.txt        # RAW-ключи (до кодирования)
├── cookies/            # Cookies авторизации
└── 3xcsm.log          # Лог работы

/var/www/3xcsm/
└── sub.txt             # Файл подписки (раздаётся Nginx)

/usr/local/bin/3xsub    # Команда быстрого запуска
/etc/nginx/sites-available/3xcsm  # Конфигурация Nginx
```

---

## Поддерживаемые VPN-клиенты

| Клиент | Платформа | Поддержка подписки |
|--------|-----------|-------------------|
| **Hiddify** | Android, iOS, Windows, macOS, Linux | ✅ Полная |
| **Happ** | Android, iOS, Windows, macOS, Linux | ✅ Полная |
| **v2rayNG** | Android | ✅ Полная |
| **v2rayN** | Windows | ✅ Полная |
| **Nekoray** | Windows, Linux | ✅ Полная |
| **Streisand** | iOS, macOS | ✅ Полная |
| **Clash Verge** | Windows, macOS, Linux | ⚠️ Частичная |

---

## Заголовки подписки

Скрипт поддерживает стандартные заголовки подписки, которые будут отображаться в VPN-клиенте, каждый из которых можно включить или отключить отдельно:

| Заголовок | Описание | По умолчанию |
|-----------|----------|-------------|
| `#profile-title` | Название подписки в клиенте | ✅ Включён |
| `#profile-update-interval` | Интервал автообновления (часы) | ✅ Включён |
| `#support-url` | Ссылка на поддержку / Telegram | ❌ Выключен |
| `#profile-web-page-url` | Веб-страница подписки | ❌ Выключен |
| `#subscription-userinfo` | Трафик, лимит, срок действия | ❌ Выключен |

> ⚠️ Некоторые клиенты не поддерживают заголовки. А так же добавление подписки по URL без SSL (HTTPS)
> ⚠️ При проблемах с этим, отключите все или часть заголовков через меню.

---

## Часто задаваемые вопросы

<details>
<summary><b>Подписка не открывается в браузере</b></summary>

1. Зайдите в меню **Файл подписки → 7) Проверить доступность URL**
2. Скрипт покажет причину и предложит авто-восстановление
3. Убедитесь, что порт открыт в firewall вашего VPS-провайдера

</details>

<details>
<summary><b>Ключи не собираются с панели</b></summary>

- Проверьте версию 3x-UI (нужна 2.4.0+)
- Проверьте Web Base Path (вводить БЕЗ слешей)
- Попробуйте переключить HTTP/HTTPS
- Запустите с отладкой: `DEBUG=1 3xsub`

</details>

<details>
<summary><b>Как обновить скрипт?</b></summary>

Просто запустите установку заново — она обновит скрипт, сохранив конфигурацию:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ВАШ_ЮЗЕРНЕЙМ/ВАШ_РЕПОЗИТОРИЙ/main/install.sh)
```

</details>

---

## Автор

- **LarsGravesen**
- Telegram: [t.me/LarsInvilink](https://t.me/LarsInvilink)

---

## Лицензия

Этот проект распространяется под лицензией [MIT](LICENSE).

---

<p align="center">
  <sub>Если проект оказался полезным — поставьте ⭐ на GitHub</sub>
</p>
