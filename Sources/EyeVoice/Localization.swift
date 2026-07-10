import Foundation

enum UILanguage: String {
    case ru, en
}

struct Strings {
    let audioSource: String
    let tabMic: String
    let tabSystem: String
    let tabApps: String
    let micTitle: String
    let micSub: String
    let systemTitle: String
    let systemSub: String
    let permissionHint: String
    let allTabs: String
    let tabHint: String
    let translation: String
    let from: String
    let to: String
    let mode: String
    let modeSync: String
    let modeSyncHint: String
    let modeVoice: String
    let modeVoiceHint: String
    let voice: String
    let listenHint: String
    let autoStop: String
    let stopOnIdle: String
    let guardHint: String
    let start: String
    let stop: String
    let quit: String
    let statusIdle: String
    let statusConnecting: String
    let statusListening: String
    let statusTranslating: String
    let statusStandby: String
    let statusError: String
    let notifTitle: String
    let notifBody: String
    let languageNames: [String: String]

    func languageName(_ english: String) -> String {
        languageNames[english] ?? english
    }

    static let en = Strings(
        audioSource: "AUDIO SOURCE",
        tabMic: "MIC",
        tabSystem: "SYSTEM",
        tabApps: "APPS",
        micTitle: "MICROPHONE",
        micSub: "your voice → translated aloud",
        systemTitle: "SYSTEM AUDIO",
        systemSub: "everything the mac plays",
        permissionHint: "app / system capture needs the Screen Recording permission",
        allTabs: "ALL TABS",
        tabHint: "audio comes from the whole browser — the chosen tab is brought to front; pause sound in other tabs",
        translation: "TRANSLATION",
        from: "FROM",
        to: "TO",
        mode: "MODE",
        modeSync: "SIMULTANEOUS",
        modeSyncHint: "lowest latency, built-in voice",
        modeVoice: "CUSTOM VOICE",
        modeVoiceHint: "pick a voice, translates phrase by phrase",
        voice: "VOICE",
        listenHint: "listen to this voice",
        autoStop: "STANDBY",
        stopOnIdle: "SLEEP ON SILENCE",
        guardHint: "8s of silence → connection sleeps (no spend);\nsound returns → resumes instantly",
        start: "[ ▶ START ]",
        stop: "[ ■ STOP ]",
        quit: "quit",
        statusIdle: "IDLE",
        statusConnecting: "CONNECTING",
        statusListening: "LISTENING",
        statusTranslating: "TRANSLATING",
        statusStandby: "STANDBY",
        statusError: "ERROR",
        notifTitle: "EyeVoice",
        notifBody: "",
        languageNames: [:]
    )

    static let ru = Strings(
        audioSource: "ИСТОЧНИК ЗВУКА",
        tabMic: "МИК",
        tabSystem: "СИСТЕМА",
        tabApps: "ПРИЛОЖЕНИЯ",
        micTitle: "МИКРОФОН",
        micSub: "твой голос → перевод вслух",
        systemTitle: "СИСТЕМНЫЙ ЗВУК",
        systemSub: "всё, что играет mac",
        permissionHint: "захват приложений и системы требует разрешения «Запись экрана»",
        allTabs: "ВСЕ ВКЛАДКИ",
        tabHint: "звук идёт со всего браузера — выбранная вкладка выводится вперёд; звук в остальных лучше поставить на паузу",
        translation: "ПЕРЕВОД",
        from: "ИЗ",
        to: "В",
        mode: "РЕЖИМ",
        modeSync: "СИНХРОННЫЙ",
        modeSyncHint: "минимальная задержка, встроенный голос",
        modeVoice: "СВОЙ ГОЛОС",
        modeVoiceHint: "выбор голоса, перевод по фразам",
        voice: "ГОЛОС",
        listenHint: "прослушать голос",
        autoStop: "РЕЖИМ СНА",
        stopOnIdle: "СОН ПРИ ТИШИНЕ",
        guardHint: "8с тишины → соединение засыпает (деньги не тратятся);\nпоявился звук → мгновенно продолжает",
        start: "[ ▶ СТАРТ ]",
        stop: "[ ■ СТОП ]",
        quit: "выход",
        statusIdle: "ОЖИДАНИЕ",
        statusConnecting: "ПОДКЛЮЧЕНИЕ",
        statusListening: "СЛУШАЮ",
        statusTranslating: "ПЕРЕВОЖУ",
        statusStandby: "В ОЖИДАНИИ",
        statusError: "ОШИБКА",
        notifTitle: "EyeVoice",
        notifBody: "",
        languageNames: [
            "Auto": "Авто", "Russian": "Русский", "English": "Английский",
            "Spanish": "Испанский", "German": "Немецкий", "French": "Французский",
            "Italian": "Итальянский", "Portuguese": "Португальский", "Chinese": "Китайский",
            "Japanese": "Японский", "Korean": "Корейский", "Ukrainian": "Украинский",
            "Turkish": "Турецкий", "Arabic": "Арабский", "Hindi": "Хинди",
        ]
    )
}
