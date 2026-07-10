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
- **Запись экрана** (System Settings → Privacy & Security → Screen & System
  Audio Recording) — для SYSTEM AUDIO и захвата звука приложений.
  После выдачи разрешения приложение нужно перезапустить.

## Где что лежит

- `Sources/EyeVoice/Realtime/RealtimeClient.swift` — WebSocket-клиент Realtime API
- `Sources/EyeVoice/Capture/` — захват: микрофон (AVAudioEngine) и приложения (ScreenCaptureKit)
- `Sources/EyeVoice/Overlay/` — виньетка и островок
- `Sources/EyeVoice/UI/ControlPanelView.swift` — панель в menu bar
- `Sources/EyeVoice/Secrets.swift` — имена моделей; API-ключ читается из переменной окружения `OPENAI_API_KEY`

## Иконка

Плейсхолдер (белый треугольник на чёрном) генерируется `Scripts/make_icon.swift`
при первой сборке. Чтобы заменить: положи свой `AppIcon.icns` в `build/` и пересобери.
