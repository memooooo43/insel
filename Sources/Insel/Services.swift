import AppKit
import CoreLocation
import IOKit.ps
import SwiftUI

/// `--snapshot`: keine echten Player abfragen, nur Beispieldaten zeigen.
var demoMode = false

func openApp(bundleID: String) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

/// Kurze Einblendung in der Insel (Laden gestartet, AirPods verbunden …).
struct IslandEvent: Equatable {
    let id = UUID()
    let icon: String
    let value: String
    let color: Color
}

// MARK: - Musik (Apple Music / Spotify per AppleScript) + Lyrics

struct LyricLine {
    let time: Double
    let text: String
}

final class MusicModel: ObservableObject {
    enum Player: String {
        case music = "Music", spotify = "Spotify", esound = "eSound"
        var bundleID: String {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            case .esound: return "com.earlystudio.esound"
            }
        }
    }

    enum LyricsState { case none, loading, loaded([LyricLine]), notFound }

    @Published var player: Player?
    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var duration: Double = 0
    @Published var artwork: NSImage?
    /// Farbe aus dem Cover; `accent` nimmt je nach Einstellung diese oder die eigene Farbe.
    @Published var coverAccent = Color(red: 0.55, green: 0.85, blue: 0.75)
    var accent: Color { Settings.shared.accentFromCover ? coverAccent : Settings.shared.fixedAccent }
    @Published var lyrics = LyricsState.none
    /// false = nur ungetimter Liedtext gefunden, Zeilen sind gleichmäßig über den Song verteilt
    @Published var lyricsSynced = true

    private var position: Double = 0
    private var polledAt = Date()

    private let esound = ESoundBridge()
    /// Nach einem Klick in der Insel gilt kurz unser Wert, bis eSound die Datei nachgezogen hat.
    private var esOverride: (playing: Bool, position: Double, at: Date)?
    private var tick = 0
    /// Letzter Stand von Apple Music/Spotify (werden seltener abgefragt)
    private var scriptStates: [(Player, State)] = []
    private var trackKey = ""
    /// Lyrics, die beim Songwechsel noch in der eSound-Datei stehen, gehören zum vorherigen Song.
    private var staleLyricsSig: String?
    /// Lyrics vom Player selbst (eSound) übernommen – dann keine eigene Suche mehr.
    private var appliedLyricsSig: String?
    /// Zuletzt gesehener ungetimter Text vom Player – Rückfall, falls LRCLIB nichts Synchrones hat
    private var playerPlainLyrics: String?
    private var timer: Timer?

    init() {
        guard !demoMode else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    var isActive: Bool { player != nil && playing && Settings.shared.showMusic }

    /// Beispieldaten für `--snapshot`.
    func loadDemo() {
        timer?.invalidate()
        player = .music; title = "Neon Nights"; artist = "Demo Artist"; playing = true
        duration = 214; position = 83; polledAt = Date()
        coverAccent = Color(red: 0.55, green: 0.9, blue: 0.6)
        lyrics = .loaded([LyricLine(time: 80, text: "Driving through the city lights tonight"), LyricLine(time: 90, text: "Nothing else but you and I")])
    }

    /// Aktuelle Wiedergabeposition, zwischen den Abfragen hochgerechnet.
    func position(at date: Date) -> Double {
        guard playing else { return position }
        return min(duration, position + date.timeIntervalSince(polledAt))
    }

    /// Index der gerade gesungenen Zeile; -1 vor der ersten Zeile.
    func lyricIndex(at date: Date) -> Int {
        guard case .loaded(let lines) = lyrics, !lines.isEmpty else { return -1 }
        let pos = position(at: date) + 0.3 + Settings.shared.lyricsOffset
        return lines.lastIndex(where: { $0.time <= pos }) ?? -1
    }

    func playPause() {
        guard let player else { openApp(bundleID: Player.music.bundleID); return }
        command("playpause", player)
    }

    func next() { if let player { command("next track", player) } }
    func previous() { if let player { command("previous track", player) } }

    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        if player == .esound {
            // eSound kann nur in 15-s-Schritten springen – so oft „Vor-/Zurückspringen“ wie nötig
            let now = Date()
            let current = position(at: now)
            let steps = Int(((fraction * duration - current) / ESoundBridge.skipSeconds).rounded())
            guard steps != 0, esound.press(steps > 0 ? .forward : .backward, times: abs(steps)) else { return }
            log("eSound: \(steps > 0 ? "vor" : "zurück") × \(abs(steps))")
            // Uhr sofort mitziehen, damit Balken und Lyrics nicht erst hinterherhinken
            let target = min(max(current + Double(steps) * ESoundBridge.skipSeconds, 0), duration)
            esOverride = (playing, target, now)
            position = target; polledAt = now
            objectWillChange.send()
            return
        }
        command("set player position to \(String(format: "%.2f", fraction * duration))", player)
    }

    func openPlayer() { openApp(bundleID: (player ?? .music).bundleID) }

    private func command(_ cmd: String, _ p: Player) {
        if p == .esound {
            // eSound hat keine AppleScript-Schnittstelle
            // Bevorzugt über das eSound-Menü (trifft sicher eSound), sonst Medientasten
            let commands: [String: (ESoundBridge.Command, Int32)] = [
                "playpause": (.playPause, MediaKeys.play), "next track": (.next, MediaKeys.next),
                "previous track": (.previous, MediaKeys.previous),
            ]
            if let (menu, key) = commands[cmd], !esound.press(menu) { MediaKeys.post(key) }
            if cmd == "playpause" {
                // Sofort umschalten statt auf die Datei zu warten
                let now = Date()
                esOverride = (!playing, position(at: now), now)
                position = esOverride!.position; polledAt = now; playing.toggle()
                return
            }
        } else {
            Self.run("tell application \"\(p.rawValue)\" to \(cmd)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poll() }
    }

    private struct State {
        let playing: Bool, title: String, artist: String, album: String, duration: Double, position: Double
        var artworkURL: URL? = nil
        var lyrics: [LyricLine] = []
        /// Ungetimter Liedtext vom Player (eSound holt ihn z. B. von Genius)
        var plainLyrics: String? = nil
    }

    private func poll() {
        // Nur abfragen, was schon läuft – sonst würde AppleScript die App starten.
        let s = Settings.shared
        let enabled: [Player] = (s.sourceESound ? [.esound] : []) + (s.sourceSpotify ? [.spotify] : []) + (s.sourceAppleMusic ? [.music] : [])
        let running = enabled.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }

        // eSound ist billig (Datei lesen) – bei jedem Takt. Apple Music/Spotify gehen über AppleScript,
        // und das blockiert, bis die App antwortet: nur einmal pro Sekunde und nicht, während eSound spielt.
        let esound = running.contains(.esound) ? state(of: .esound).map { (Player.esound, $0) } : nil
        tick += 1
        var scriptFresh = false
        if esound?.1.playing == true {
            scriptStates = []
        } else if tick % 4 == 0 || player == nil && scriptStates.isEmpty {
            scriptStates = running.filter { $0 != .esound }.compactMap { p in state(of: p).map { (p, $0) } }
            scriptFresh = true
        }
        let states = (esound.map { [$0] } ?? []) + scriptStates
        guard let (p, s) = states.first(where: { $0.1.playing }) ?? states.first else {
            if player != nil {
                player = nil; playing = false; title = ""; artist = ""; artwork = nil; lyrics = .none; trackKey = ""
            }
            return
        }
        if player != p { player = p }
        if playing != s.playing { playing = s.playing }
        if title != s.title { title = s.title }
        if artist != s.artist { artist = s.artist }
        if duration != s.duration { duration = s.duration }
        let key = "\(p.rawValue)|\(s.title)|\(s.artist)"
        // Eigene Uhr gleichmäßig weiterlaufen lassen und nur bei echter Abweichung (Spulen, Hänger)
        // neu stellen – die gelesene Position schwankt um ein paar Zehntel, das ließ die Lyrics an
        // Zeilengrenzen vor- und zurückspringen.
        let now = Date()
        // Zwischengespeicherte Apple-Music/Spotify-Werte sind bis zu 1 s alt – deren Position nicht übernehmen
        let positionFresh = p == .esound || scriptFresh
        if positionFresh, !(s.playing && key == trackKey && abs(s.position - position(at: now)) < 0.6) {
            position = s.position
            polledAt = now
        }
        if key != trackKey {
            let wasPlaying = !trackKey.isEmpty
            trackKey = key
            loadArtwork(p, url: s.artworkURL)
            staleLyricsSig = wasPlaying ? (!s.lyrics.isEmpty ? Self.signature(s.lyrics) : s.plainLyrics) : nil
            appliedLyricsSig = nil
            lyrics = .loading
            // eSound lädt seine Lyrics erst kurz nach dem Wechsel – eigene Suche nur, wenn dann keine kommen
            playerPlainLyrics = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + (p == .esound ? 2.5 : 0)) { [weak self] in
                guard let self, self.trackKey == key, self.appliedLyricsSig == nil else { return }
                self.loadLyrics(s, key: key, plain: self.playerPlainLyrics)
            }
        }
        if let plain = s.plainLyrics, plain.hashValue != staleLyricsSig?.hashValue { playerPlainLyrics = plain }
        // Neue Lyrics vom Player übernehmen, sobald sie in der Datei stehen
        if !s.lyrics.isEmpty {
            let sig = Self.signature(s.lyrics)
            if sig != staleLyricsSig, sig != appliedLyricsSig {
                appliedLyricsSig = sig
                lyricsSynced = true
                lyrics = .loaded(s.lyrics)
            }
        }
    }

    private func state(of p: Player) -> State? {
        if p == .esound { return esoundState() }
        let src = """
        tell application "\(p.rawValue)"
            set s to player state as string
            if s is "stopped" then return s
            set t to current track
            return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (duration of t) & linefeed & (player position)
        end tell
        """
        guard let out = Self.run(src)?.stringValue else { return nil }
        let parts = out.components(separatedBy: "\n")
        guard parts.count >= 6 else { return nil }
        // Zahlen kommen je nach Systemsprache mit Komma
        let number = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        var duration = number(parts[4])
        if p == .spotify { duration /= 1000 } // Spotify liefert Millisekunden
        return State(playing: parts[0] == "playing", title: parts[1], artist: parts[2], album: parts[3],
                     duration: duration, position: number(parts[5]))
    }

    private func loadArtwork(_ p: Player, url: URL?) {
        artwork = nil
        switch p {
        case .esound:
            guard let url else { return }
            let key = trackKey
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self?.trackKey == key { self?.setArtwork(image) } }
            }.resume()
        case .music:
            if let data = Self.run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data,
               let image = NSImage(data: data) {
                setArtwork(image)
            }
        case .spotify:
            guard let s = Self.run("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                  let url = URL(string: s) else { return }
            let key = trackKey
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self?.trackKey == key { self?.setArtwork(image) } }
            }.resume()
        }
    }

    private func setArtwork(_ image: NSImage) {
        artwork = image
        if let c = Self.accentColor(of: image) { coverAccent = c }
    }

    // MARK: eSound

    private static let esoundFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/eSound Music/esound_playback.json")

    /// Alles kommt aus esound_playback.json. Beim Abspielen schreibt eSound die Datei jede Sekunde neu
    /// (mit aktueller Position), beim Pausieren hört es sofort auf. Das Feld „userPaused“ ist dagegen
    /// unzuverlässig, und die Tonausgabe bleibt nach dem Pausieren noch ~10 s aktiv.
    private func esoundState() -> State? {
        guard let data = try? Data(contentsOf: Self.esoundFile),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshotString = d["currentItemSnapshot"] as? String,
              let snapshot = try? JSONSerialization.jsonObject(with: Data(snapshotString.utf8)) as? [String: Any],
              let item = snapshot["item"] as? [String: Any],
              let title = item["name"] as? String else { return nil }

        let artists = (item["artists"] as? [[String: Any]] ?? [])
            .compactMap { ($0["artist"] as? [String: Any])?["name"] as? String }
        let album = (item["album"] as? [String: Any])?["name"] as? String ?? ""
        // eSound speichert die meisten Werte als Text ("true", "136.6")
        let bool = { (v: Any?) -> Bool? in (v as? Bool) ?? (v as? String).map { $0 == "true" } }
        let number = { (v: Any?) -> Double? in (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
        let duration = number(d["duration"]) ?? number(item["duration"]) ?? 0
        let now = Date()
        // Über FileManager statt URL.resourceValues – letzteres hält den Wert im Zwischenspeicher
        let written = (try? FileManager.default.attributesOfItem(atPath: Self.esoundFile.path))?[.modificationDate] as? Date ?? .distantPast
        let elapsed = number(d["elapsedTime"]) ?? 0

        // Pausiert, wenn eSound es meldet (schreibt beim Pausieren sofort userPaused: true) oder
        // die Datei länger nicht geschrieben hat – beim Abspielen schreibt eSound jede Sekunde.
        // (Pausieren per Medientaste setzt userPaused nicht, daher beides.)
        let fileFresh = now.timeIntervalSince(written) < 1.5
        var playing = fileFresh && bool(d["userPaused"]) != true
        var position = playing ? elapsed + now.timeIntervalSince(written) : elapsed

        if let o = esOverride {
            // Unser Wert gilt, bis eSound nach dem Klick mindestens einmal geschrieben hat (max. 3 s)
            let fileCaughtUp = written > o.at.addingTimeInterval(0.3) && (playing == o.playing)
            if fileCaughtUp || now.timeIntervalSince(o.at) > 3 {
                esOverride = nil
            } else {
                playing = o.playing
                position = o.position + (o.playing ? now.timeIntervalSince(o.at) : 0)
            }
        }

        // Synchron: [{time, verse}] – ungetimt (z. B. von Genius): nur [{verse}]
        var lyrics: [LyricLine] = []
        var plain: String?
        if let raw = d["lyrics"] as? String,
           let lines = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]], !lines.isEmpty {
            if bool(d["syncedLyrics"]) == true {
                lyrics = lines.compactMap { l in
                    guard let t = number(l["time"]), let v = l["verse"] as? String else { return nil }
                    return LyricLine(time: t, text: v.isEmpty ? "♪" : v)
                }
            } else {
                plain = lines.compactMap { $0["verse"] as? String }.joined(separator: "\n")
            }
        }

        let thumb = (item["thumbnailL"] as? String) ?? (item["thumbnailM"] as? String)
        return State(playing: playing, title: title, artist: artists.joined(separator: ", "), album: album,
                     duration: duration, position: min(max(position, 0), duration),
                     artworkURL: thumb.flatMap(URL.init(string:)), lyrics: lyrics, plainLyrics: plain)
    }

    // MARK: Lyrics über LRCLIB (kostenlos, ohne Account)

    private struct LrcLib: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    /// Sucht bei LRCLIB in mehreren Anläufen – vom genauesten zum lockersten.
    /// Synchronisierte Lyrics haben Vorrang, sonst wird reiner Liedtext genommen.
    private func loadLyrics(_ s: State, key: String, plain: String? = nil) {
        let title = Self.cleanTitle(s.title), artist = Self.firstArtist(s.artist)
        let duration = String(Int(s.duration.rounded()))
        func url(_ path: String, _ items: [(String, String)]) -> URL {
            var c = URLComponents(string: "https://lrclib.net/api/\(path)")!
            c.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
            return c.url!
        }
        let attempts = [
            url("get", [("track_name", s.title), ("artist_name", s.artist), ("album_name", s.album), ("duration", duration)]),
            url("get", [("track_name", title), ("artist_name", artist), ("duration", duration)]),
            url("search", [("track_name", title), ("artist_name", artist)]),
            url("search", [("q", "\(title) \(artist)")]),
        ]
        tryLyrics(attempts, key: key, duration: s.duration, plain: plain)
    }

    private func tryLyrics(_ urls: [URL], key: String, duration: Double, plain: String?) {
        guard trackKey == key, appliedLyricsSig == nil else { return }
        guard let url = urls.first else { finishLyrics(synced: nil, plain: plain, key: key, duration: duration); return }
        Self.fetchData(url) { data in
            // /get liefert ein Objekt, /search eine Liste
            let decoder = JSONDecoder()
            let hits = data.flatMap { (try? decoder.decode([LrcLib].self, from: $0)) ?? (try? decoder.decode(LrcLib.self, from: $0)).map { [$0] } } ?? []
            // Nur Treffer mit passender Länge – sonst stimmt das Timing nicht (andere Version)
            let fits = hits.filter { h in duration <= 0 || h.duration.map { abs($0 - duration) < 8 } ?? true }
            if let synced = fits.first(where: { $0.syncedLyrics?.isEmpty == false })?.syncedLyrics {
                self.finishLyrics(synced: synced, plain: nil, key: key, duration: duration)
                return
            }
            let plainHit = plain ?? fits.first(where: { $0.plainLyrics?.isEmpty == false })?.plainLyrics
            DispatchQueue.main.async { self.tryLyrics(Array(urls.dropFirst()), key: key, duration: duration, plain: plainHit) }
        }
    }

    private func finishLyrics(synced: String?, plain: String?, key: String, duration: Double) {
        var lines = synced.map(Self.parseLRC) ?? []
        let isSynced = !lines.isEmpty
        if lines.isEmpty, let plain {
            // Ungetimten Text gleichmäßig über den Song verteilen – besser als gar nichts
            // Leerzeilen und Abschnitts-Überschriften wie „[Refrain]“ weglassen
            let texts = plain.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }
            lines = texts.enumerated().map { i, text in
                LyricLine(time: duration * (0.08 + 0.85 * Double(i) / Double(max(texts.count, 1))), text: text)
            }
        }
        DispatchQueue.main.async {
            guard self.trackKey == key, self.appliedLyricsSig == nil else { return }
            self.lyricsSynced = isSynced
            self.lyrics = lines.isEmpty ? .notFound : .loaded(lines)
        }
    }

    private static func fetchData(_ url: URL, done: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Insel/1.0 (https://github.com/memooooo43/insel)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            done((response as? HTTPURLResponse)?.statusCode == 200 ? data : nil)
        }.resume()
    }

    /// „Song (feat. X) - 2011 Remaster“ → „Song“
    static func cleanTitle(_ title: String) -> String {
        var t = title
        for pattern in [
            #"\s*[\(\[](feat\.?|ft\.?|with|prod\.?)\s[^\)\]]*[\)\]]"#,
            #"\s*[\(\[][^\)\]]*(remaster|version|edit|live|mono|stereo)[^\)\]]*[\)\]]"#,
            #"\s+-\s+.*(remaster|version|edit|live).*$"#,
        ] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// „A, B & C“ → „A“
    static func firstArtist(_ artist: String) -> String {
        let first = artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? artist
        return first.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|x)\s.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func signature(_ lines: [LyricLine]) -> String {
        "\(lines.count)|\(lines.first?.time ?? 0)|\(lines.first?.text ?? "")"
    }

    /// "[01:23.45] Text" → LyricLine
    private static func parseLRC(_ text: String) -> [LyricLine] {
        text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let s = Double(stamp[1]) else { return nil }
            let words = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return LyricLine(time: m * 60 + s, text: words.isEmpty ? "♪" : words)
        }
    }

    /// Mittlere Farbe des Covers, aufgehellt – für Equalizer und Fortschrittsbalken.
    private static func accentColor(of image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(max(s, 0.35), 0.8), brightness: max(b, 0.85))
    }

    @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}

// MARK: - Medientasten

/// Sendet Play/Pause, Weiter, Zurück wie die Medientasten der Tastatur.
/// Braucht einmalig die Freigabe unter „Bedienungshilfen“.
enum MediaKeys {
    static let play: Int32 = 16      // NX_KEYTYPE_PLAY
    static let next: Int32 = 17      // NX_KEYTYPE_NEXT
    static let previous: Int32 = 18  // NX_KEYTYPE_PREVIOUS

    static func post(_ key: Int32) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Akku

final class BatteryModel: ObservableObject {
    @Published var level = 100
    @Published var charging = false
    @Published var pluggedIn = false
    @Published var hasBattery = false
    var onPluggedIn: (() -> Void)?
    private var source: CFRunLoopSource?

    init() {
        read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryModel>.fromOpaque(ctx).takeUnretainedValue().read()
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    var symbol: String {
        if charging || pluggedIn { return "battery.100percent.bolt" }
        switch level {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 11...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var color: Color {
        if charging || pluggedIn { return .green }
        return level <= 20 ? .red : .white
    }

    private func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let wasPlugged = pluggedIn
            hasBattery = true
            level = d[kIOPSCurrentCapacityKey] as? Int ?? level
            charging = d[kIOPSIsChargingKey] as? Bool ?? false
            pluggedIn = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if pluggedIn && !wasPlugged { onPluggedIn?() }
        }
    }
}

// MARK: - AirPods (Akkustand über system_profiler)

final class AirPodsModel: ObservableObject {
    struct Device: Equatable {
        let name: String
        let left: Int?, right: Int?, caseLevel: Int?, main: Int?
        var lowest: Int? { [left, right, main].compactMap { $0 }.min() }
        var icon: String { name.localizedCaseInsensitiveContains("max") ? "airpodsmax" : name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones" }
    }

    @Published var devices: [Device] = []
    var onConnect: ((Device) -> Void)?
    private var known: Set<String>?
    private var timer: Timer?

    init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async {
            let found = Self.read()
            DispatchQueue.main.async {
                let names = Set(found.map(\.name))
                if let known = self.known {
                    for d in found where !known.contains(d.name) { self.onConnect?(d) }
                }
                self.known = names
                if self.devices != found { self.devices = found }
            }
        }
    }

    private static func read() -> [Device] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = bt["device_connected"] as? [[String: [String: Any]]] else { return [] }
        let pct = { (v: Any?) -> Int? in (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
        return connected.flatMap { $0 }.compactMap { name, props in
            let d = Device(name: name, left: pct(props["device_batteryLevelLeft"]), right: pct(props["device_batteryLevelRight"]),
                           caseLevel: pct(props["device_batteryLevelCase"]), main: pct(props["device_batteryLevelMain"]))
            return d.lowest == nil ? nil : d
        }
    }
}

// MARK: - Wetter (Open-Meteo, ohne Account)

final class WeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: Int?
    @Published var code = 0
    @Published var isDay = true

    private let locationManager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var timer: Timer?

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }

    private struct Geocoding: Decodable {
        struct Result: Decodable {
            let latitude: Double
            let longitude: Double
        }
        let results: [Result]?
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        start()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.start() }
    }

    var city: String? { UserDefaults.standard.string(forKey: "city").flatMap { $0.isEmpty ? nil : $0 } }

    func setCity(_ name: String?) {
        UserDefaults.standard.set(name, forKey: "city")
        start()
    }

    func start() {
        if let city { geocode(city); return }
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted: break
        default: locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if city == nil, manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        fetch()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if coordinate != nil { fetch() }
    }

    private func geocode(_ city: String) {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "de")]
        URLSession.shared.dataTask(with: comps.url!) { [weak self] data, _, _ in
            guard let data, let r = try? JSONDecoder().decode(Geocoding.self, from: data).results?.first else { return }
            DispatchQueue.main.async {
                self?.coordinate = CLLocationCoordinate2D(latitude: r.latitude, longitude: r.longitude)
                self?.fetch()
            }
        }.resume()
    }

    private func fetch() {
        guard let c = coordinate else { return }
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m,weather_code,is_day")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let f = try? JSONDecoder().decode(Forecast.self, from: data) else { return }
            DispatchQueue.main.async {
                self?.temperature = Int(f.current.temperature_2m.rounded())
                self?.code = f.current.weather_code
                self?.isDay = f.current.is_day == 1
            }
        }.resume()
    }

    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Ablage (Datei-Tray)

final class TrayModel: ObservableObject {
    @Published var files: [URL] = []

    init() {
        files = (UserDefaults.standard.stringArray(forKey: "tray") ?? [])
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self.add(url) }
            }
        }
    }

    func add(_ url: URL) {
        guard !files.contains(url) else { return }
        files.append(url)
        save()
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        files = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(files.map(\.path), forKey: "tray")
    }
}
