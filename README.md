<p align="center">
  <img src="https://img.shields.io/badge/version-1.0-blue?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/platform-Linux-orange?style=for-the-badge&logo=linux&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/shell-bash-121011?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Shell">
  <img src="https://img.shields.io/badge/3x--ui-v2.4%2B-blueviolet?style=for-the-badge" alt="3x-ui">
</p>

<h1 align="center">3X-UI CSM — CLI Subscription Manager</h1>

<p align="center">
  <b>CLI-инструмент для автоматического сбора VPN-ключей с панелей 3x-UI<br>и формирования единого файла подписки с раздачей через Nginx.</b>
</p>

<p align="center">
  <a href="https://t.me/LarsInvilink">
    <img src="https://img.shields.io/badge/Telegram-Профиль-blue?style=flat-square&logo=telegram" alt="Telegram">
  </a>
</p>

---

## Что это?

**3X-UI CSM** — bash-скрипт для VPS, который подключается к одной или нескольким панелям **3x-UI**, собирает VPN-ключи со всех выбранных инбаундов и клиентов, формирует единый файл подписки и раздаёт его через **Nginx** по HTTP или HTTPS.

Один URL подписки — все серверы — все VPN-клиенты.

---

## Поддерживаемые протоколы

| Протокол | Поддержка |
|----------|-----------|
| **VLESS** (Reality, TLS, WS, gRPC, TCP, H2, httpupgrade, splithttp) | ✅ |
| **VMess** | ✅ |
| **Trojan** | ✅ |
| **Shadowsocks** | ✅ |
| **Hysteria2** | ✅ |

---

## Возможности

- Мульти-сервер: добавление нескольких панелей 3x-UI
- Выбор конкретных инбаундов и клиентов для каждого сервера
- Автообновление подписки по расписанию (cron: минуты/часы/дни)
- Поддержка домена с автоматическим SSL (Let's Encrypt)
- Кодирование URL-пути и содержимого файла (base64)
- Настройка заголовков подписки (profile-title, update-interval, support-url, userinfo)
- QR-код подписки прямо в терминале
- Диагностика доступности URL с авто-восстановлением
- Обзор текущего состояния подписки
- Шифрование паролей серверов (AES-256)
- Полный сброс настроек и удаление скрипта

---

## Требования

- **ОС:** Ubuntu 20.04+ / Debian 11+ (или любой Linux с `apt`)
- **Права:** root
- **3x-UI:** версия 2.4.0+ (рекомендуется 2.5.0+)

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

После установки:

```bash
3xsub
```

---

## Структура файлов

| Путь | Описание |
|------|----------|
| `/opt/3xcsm/3xcsm.sh` | Основной скрипт |
| `/opt/3xcsm/config.json` | Конфигурация |
| `/opt/3xcsm/servers.json` | Список серверов (пароли зашифрованы) |
| `/opt/3xcsm/raw_keys.txt` | RAW-ключи до кодирования |
| `/var/www/3xcsm/sub.txt` | Файл подписки (раздаётся Nginx) |
| `/usr/local/bin/3xsub` | Команда быстрого запуска |

---

## Поддерживаемые VPN-клиенты

| Клиент | Платформа | Подписка |
|--------|-----------|----------|
| **Hiddify** | Android, iOS, Windows, macOS, Linux | ✅ |
| **Happ** | Android, iOS, Windows, macOS, Linux | ✅ |
| **v2rayNG** | Android | ✅ |
| **v2rayN** | Windows | ✅ |
| **Nekoray** | Windows, Linux | ✅ |
| **Streisand** | iOS, macOS | ✅ |
| **Clash Verge** | Windows, macOS, Linux | ⚠️ Частичная |

---

## Документация

Подробная пошаговая инструкция: **[Instruction.md](Instruction.md)**

---

## Автор

- **LarsGravesen**
- Telegram: [t.me/LarsInvilink](https://t.me/LarsInvilink)
- GitHub: [github.com/LarsGravesen-invilink/3x-ui-csm](https://github.com/LarsGravesen-invilink/3x-ui-csm)

---

## Лицензия

[MIT](LICENSE)

---

<p align="center">
  <sub>Если проект полезен — поставьте ⭐ на GitHub</sub>
</p>
![Uploading Screenshot_2026-05-16-15-30-31-35_99c04817c0de5652397fc8b56c3b3817.jpg…]()
