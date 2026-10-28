import AppKit

/// Steuert eSound über die Bedienungshilfen: Befehle aus dem eSound-Menü „Wiedergabe“.
final class ESoundBridge {
    static let bundleID = "com.earlystudio.esound"

    /// So weit springt „Vorspringen“/„Zurückspringen“ in eSound (gemessen).
    static let skipSeconds: Double = 15

    // MARK: Menü „Wiedergabe“ (Bedienungshilfen)

    enum Command {
        case playPause, next, previous, forward, backward

        /// Menütitel je nach Sprache von eSound
        var titles: [String] {
            switch self {
            case .playPause: return ["Wiedergabe/Pause", "Play/Pause"]
            case .next: return ["Nächster Titel", "Next Track", "Next"]
            case .previous: return ["Vorheriger Titel", "Previous Track", "Previous"]
            case .forward: return ["Vorspringen", "Skip Forward", "Seek Forward"]
            case .backward: return ["Zurückspringen", "Skip Backward", "Seek Backward"]
            }
        }
    }

    /// Löst einen Befehl aus dem eSound-Menü aus – im Hintergrund, eSound kommt nicht nach vorne.
    @discardableResult
    func press(_ command: Command, times: Int = 1) -> Bool {
        guard AXIsProcessTrusted() else { log("eSound: keine Bedienungshilfen-Freigabe"); return false }
        guard let item = menuItem(command) else { log("eSound: Menüpunkt \(command.titles[0]) nicht gefunden"); return false }
        for _ in 0..<max(times, 0) {
            guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { return false }
        }
        return true
    }

    private func menuItem(_ command: Command) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first,
              let menuBar = Self.value(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute) else { return nil }
        for top in Self.children(menuBar as! AXUIElement) where ["Wiedergabe", "Playback", "Controls"].contains(Self.string(top, kAXTitleAttribute) ?? "") {
            for menu in Self.children(top) {
                if let item = Self.children(menu).first(where: { command.titles.contains(Self.string($0, kAXTitleAttribute) ?? "") }) {
                    return item
                }
            }
        }
        return nil
    }

    private static func value(_ e: AXUIElement, _ attr: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
    }

    private static func string(_ e: AXUIElement, _ attr: String) -> String? { value(e, attr) as? String }
    private static func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
}

/// Kleines Protokoll unter ~/Library/Logs/Insel.log – hilft, wenn etwas mit eSound nicht klappt.
func log(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Insel.log")
    let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
