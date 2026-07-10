import Foundation

struct BrowserTab: Identifiable, Hashable {
    let windowIndex: Int
    let tabIndex: Int
    let title: String
    var id: String { "\(windowIndex):\(tabIndex)" }
}

/// Lists and activates browser tabs via AppleScript (Chromium dictionary + Safari variant).
/// Note: macOS audio capture is per-process, so audio always comes from the whole
/// browser — selecting a tab brings it to front, it can't isolate its sound.
enum TabLister {
    static func isBrowser(_ app: AppInfo) -> Bool {
        let hay = (app.bundleID + " " + app.name).lowercased()
        return ["chrome", "safari", "edge", "brave", "vivaldi", "opera", "yandex", "comet", "arc", "browser"]
            .contains { hay.contains($0) }
    }

    private static func isSafari(_ app: AppInfo) -> Bool {
        app.bundleID == "com.apple.Safari"
    }

    static func listTabs(for app: AppInfo, completion: @escaping ([BrowserTab]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let titleProp = isSafari(app) ? "name" : "title"
            let script = """
            tell application id "\(app.bundleID)"
                set out to ""
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    set ti to 0
                    repeat with t in tabs of w
                        set ti to ti + 1
                        set out to out & (wi as string) & tab & (ti as string) & tab & (\(titleProp) of t) & linefeed
                    end repeat
                end repeat
                return out
            end tell
            """
            let output = runAppleScript(script)
            let tabs: [BrowserTab] = output.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3,
                      let w = Int(parts[0]), let t = Int(parts[1]) else { return nil }
                let title = String(parts[2]).trimmingCharacters(in: .whitespaces)
                return BrowserTab(windowIndex: w, tabIndex: t, title: title.isEmpty ? "untitled" : title)
            }
            DispatchQueue.main.async { completion(tabs) }
        }
    }

    static func activate(_ tab: BrowserTab, in app: AppInfo) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script: String
            if isSafari(app) {
                script = """
                tell application id "\(app.bundleID)"
                    tell window \(tab.windowIndex) to set current tab to tab \(tab.tabIndex)
                    set index of window \(tab.windowIndex) to 1
                    activate
                end tell
                """
            } else {
                script = """
                tell application id "\(app.bundleID)"
                    set active tab index of window \(tab.windowIndex) to \(tab.tabIndex)
                    set index of window \(tab.windowIndex) to 1
                    activate
                end tell
                """
            }
            _ = runAppleScript(script)
        }
    }

    private static func runAppleScript(_ source: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
