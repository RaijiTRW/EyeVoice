# ▲ EyeVoice

Реалтайм голос-в-голос переводчик для macOS. Открывается в обычном окне,
остаётся доступным в menu bar и переводит через OpenAI Realtime API
(`gpt-realtime-2.1-mini`). Закрытие главного окна скрывает приложение, но не
останавливает его; для полного выхода используйте «Завершить EyeVoice».

## Сборка и запуск

```bash
Scripts/build_app.sh
open build/EyeVoice.app
```

Требуется macOS 14+ и Command Line Tools (Xcode не нужен).

## Как пользоваться

1. Кликни `▲` в menu bar.
2. Выбери источник звука:
   - `MICROPHONE` — твой голос;
   - `SYSTEM AUDIO` — весь звук системы;
   - любое запущенное приложение — только его звук (Zoom, Chrome, Telegram…).
3. Выбери языки FROM → TO и голос.
4. `[ ▶ START ]` — появится затемнение по краям экрана и островок снизу
   с волной, статусом (LISTENING / TRANSLATING) и субтитрами перевода.

## Разрешения macOS

При первом запуске система спросит:

- **Микрофон** — для источника MICROPHONE;
- **Запись системного аудио** — для SYSTEM AUDIO и звука выбранных приложений.
  EyeVoice использует Core Audio Process Tap и не запрашивает запись экрана.

## Где что лежит

- `Sources/EyeVoice/Realtime/RealtimeClient.swift` — WebSocket-клиент Realtime API
- `Sources/EyeVoice/Capture/` — захват: микрофон (AVAudioEngine) и приложения (Core Audio Process Tap)
- `Sources/EyeVoice/Overlay/` — виньетка и островок
- `Sources/EyeVoice/UI/ControlPanelView.swift` — панель в menu bar
- `Sources/EyeVoice/Update/` — Sparkle и мягкие уведомления об обновлениях
- `Sources/EyeVoice/Secrets.swift` — имена используемых моделей

Постоянный ключ OpenAI хранится только в Supabase Edge Function. Приложение
получает короткоживущий Realtime-токен после авторизации.

## Выпуск новой версии

```bash
# Версия и возрастающий внутренний build number
Scripts/release.sh 1.2.0 2

# После проверки DMG и appcast
Scripts/publish_release.sh 1.2.0
```

Сайт всегда скачивает `EyeVoice-latest.dmg`, а Sparkle получает конкретный
версионный файл из `appcast.xml`. Поэтому для следующего релиза достаточно
выполнить эти две команды с новой версией и возрастающим build number.

Готовые файлы появляются в `build/releases/`. Для публичного выпуска нужен
сертификат `Developer ID Application` и профиль `notarytool`, имя которого
передаётся через `EYEVOICE_NOTARY_PROFILE`. Без него скрипт создаёт тестовый
DMG, подписанный локальным Apple Development-сертификатом.

## Иконка

Плейсхолдер (белый треугольник на чёрном) генерируется `Scripts/make_icon.swift`
при первой сборке. Чтобы заменить: положи свой `AppIcon.icns` в `build/` и пересобери.
