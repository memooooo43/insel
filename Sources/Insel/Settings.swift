import AppKit
import SwiftUI

/// Alle Einstellungen, die man im Einstellungsfenster ändern kann. Jede Änderung wird sofort
/// in UserDefaults gespeichert und wirkt ohne Neustart.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    // Verhalten
    @Published var openDelay: Double { didSet { save(openDelay, "openDelay") } }
    @Published var closeDelay: Double { didSet { save(closeDelay, "closeDelay") } }

    // Funktionen
    @Published var showTray: Bool { didSet { save(showTray, "showTray") } }
    @Published var showBattery: Bool { didSet { save(showBattery, "showBattery") } }
    @Published var notifyCharging: Bool { didSet { save(notifyCharging, "notifyCharging") } }
    @Published var notifyAirPods: Bool { didSet { save(notifyAirPods, "notifyAirPods") } }

    // Musik
    @Published var showMusic: Bool { didSet { save(showMusic, "showMusic") } }
    @Published var sourceAppleMusic: Bool { didSet { save(sourceAppleMusic, "sourceAppleMusic") } }
    @Published var sourceSpotify: Bool { didSet { save(sourceSpotify, "sourceSpotify") } }
    @Published var sourceESound: Bool { didSet { save(sourceESound, "sourceESound") } }
    @Published var showEqualizer: Bool { didSet { save(showEqualizer, "showEqualizer") } }
    @Published var showLyrics: Bool { didSet { save(showLyrics, "showLyrics") } }
    /// Positiv = Lyrics kommen früher, negativ = später (Sekunden)
    @Published var lyricsOffset: Double { didSet { save(lyricsOffset, "lyricsOffset") } }

    // Aussehen
    @Published var liquidGlass: Bool { didSet { save(liquidGlass, "liquidGlass") } }
    /// Wie stark das Glas abgedunkelt wird (0 = klar, 1 = fast schwarz)
    @Published var glassDarkness: Double { didSet { save(glassDarkness, "glassDarkness") } }
    @Published var accentFromCover: Bool { didSet { save(accentFromCover, "accentFromCover") } }
    @Published var fixedAccent: Color { didSet { saveColor() } }
    @Published var barThickness: Double { didSet { save(barThickness, "barThickness") } }

    // Wetter
    @Published var showWeather: Bool { didSet { save(showWeather, "showWeather") } }
    @Published var fahrenheit: Bool { didSet { save(fahrenheit, "fahrenheit") } }
    /// Leer = aktueller Standort. Wird erst mit „Übernehmen“ ans Wetter weitergegeben.
    @Published var city: String

    private static let fallback: [String: Any] = [
        "openDelay": 0.1, "closeDelay": 0.35,
        "showTray": true, "showBattery": true, "notifyCharging": true, "notifyAirPods": true,
        "showMusic": true, "sourceAppleMusic": true, "sourceSpotify": true, "sourceESound": true,
        "showEqualizer": true, "showLyrics": true, "lyricsOffset": 0.0,
        "liquidGlass": true, "glassDarkness": 0.3, "accentFromCover": true, "barThickness": 7.0,
        "showWeather": true, "fahrenheit": false,
        "fixedAccent": [0.55, 0.85, 0.75],
    ]

    private init() {
        defaults.register(defaults: Self.fallback)
        openDelay = defaults.double(forKey: "openDelay")
        closeDelay = defaults.double(forKey: "closeDelay")
        showTray = defaults.bool(forKey: "showTray")
        showBattery = defaults.bool(forKey: "showBattery")
        notifyCharging = defaults.bool(forKey: "notifyCharging")
        notifyAirPods = defaults.bool(forKey: "notifyAirPods")
        showMusic = defaults.bool(forKey: "showMusic")
        sourceAppleMusic = defaults.bool(forKey: "sourceAppleMusic")
        sourceSpotify = defaults.bool(forKey: "sourceSpotify")
        sourceESound = defaults.bool(forKey: "sourceESound")
        showEqualizer = defaults.bool(forKey: "showEqualizer")
        showLyrics = defaults.bool(forKey: "showLyrics")
        lyricsOffset = defaults.double(forKey: "lyricsOffset")
        liquidGlass = defaults.bool(forKey: "liquidGlass")
        glassDarkness = defaults.double(forKey: "glassDarkness")
        accentFromCover = defaults.bool(forKey: "accentFromCover")
        barThickness = defaults.double(forKey: "barThickness")
        showWeather = defaults.bool(forKey: "showWeather")
        fahrenheit = defaults.bool(forKey: "fahrenheit")
        city = defaults.string(forKey: "city") ?? ""
        let rgb = defaults.array(forKey: "fixedAccent") as? [Double] ?? [0.55, 0.85, 0.75]
        fixedAccent = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }

    /// Alles auf Standard zurück (Stadt und Autostart bleiben).
    func reset() {
        for key in Self.fallback.keys { defaults.removeObject(forKey: key) }
        let fresh = Settings()
        openDelay = fresh.openDelay; closeDelay = fresh.closeDelay
        showTray = fresh.showTray; showBattery = fresh.showBattery
        notifyCharging = fresh.notifyCharging; notifyAirPods = fresh.notifyAirPods
        showMusic = fresh.showMusic; sourceAppleMusic = fresh.sourceAppleMusic
        sourceSpotify = fresh.sourceSpotify; sourceESound = fresh.sourceESound
        showEqualizer = fresh.showEqualizer; showLyrics = fresh.showLyrics; lyricsOffset = fresh.lyricsOffset
        liquidGlass = fresh.liquidGlass; glassDarkness = fresh.glassDarkness
        accentFromCover = fresh.accentFromCover; fixedAccent = fresh.fixedAccent; barThickness = fresh.barThickness
        showWeather = fresh.showWeather; fahrenheit = fresh.fahrenheit
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func saveColor() {
        guard let c = NSColor(fixedAccent).usingColorSpace(.sRGB) else { return }
        defaults.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: "fixedAccent")
    }

    // MARK: Beim Login starten

    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.mehmetali.insel.plist")
    }

    /// Schreibt bzw. löscht nur den LaunchAgent – wirkt ab dem nächsten Login.
    /// (launchctl bootout würde die laufende Insel sofort beenden.)
    var launchAtLogin: Bool {
        get { FileManager.default.fileExists(atPath: agentURL.path) }
        set {
            objectWillChange.send()
            if newValue {
                let plist: [String: Any] = [
                    "Label": "com.mehmetali.insel",
                    "ProgramArguments": [Bundle.main.executablePath ?? ""],
                    "RunAtLoad": true,
                    "ProcessType": "Interactive",
                ]
                try? FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                (plist as NSDictionary).write(to: agentURL, atomically: true)
            } else {
                try? FileManager.default.removeItem(at: agentURL)
            }
        }
    }
}

// MARK: - Fenster

final class SettingsWindow {
    private static var window: NSWindow?

    static func show(ui: IslandUI) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(ui: ui, settings: .shared)))
            w.title = "Insel – Einstellungen"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Gewählter Tab (eigene Klasse statt @State, siehe IslandUI).
final class SettingsTab: ObservableObject {
    @Published var selected = 0
    init(_ selected: Int = 0) { self.selected = selected }
}

struct SettingsView: View {
    let ui: IslandUI
    @ObservedObject var settings: Settings
    @ObservedObject var tab = SettingsTab()

    var body: some View {
        TabView(selection: $tab.selected) {
            general.tabItem { Label("Allgemein", systemImage: "gearshape") }.tag(0)
            music.tabItem { Label("Musik", systemImage: "music.note") }.tag(1)
            look.tabItem { Label("Aussehen", systemImage: "paintpalette") }.tag(2)
            weather.tabItem { Label("Wetter", systemImage: "cloud.sun") }.tag(3)
        }
        .frame(width: 500, height: 440)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Beim Login starten", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
            }
            Section("Öffnen & Schließen") {
                SliderRow(title: "Öffnen nach", value: $settings.openDelay, range: 0...0.6, step: 0.05, unit: "s")
                SliderRow(title: "Schließen nach", value: $settings.closeDelay, range: 0.1...1.5, step: 0.05, unit: "s")
            }
            Section("Funktionen") {
                Toggle("Ablage für Dateien", isOn: $settings.showTray)
                Toggle("Akkustand oben rechts", isOn: $settings.showBattery)
                Toggle("Hinweis beim Einstecken des Ladekabels", isOn: $settings.notifyCharging)
                Toggle("Hinweis, wenn sich AirPods verbinden", isOn: $settings.notifyAirPods)
                Button("Ablage leeren") { ui.tray.clear() }.disabled(ui.tray.files.isEmpty)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Alles zurücksetzen") { settings.reset() }
                    Button("Insel beenden") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var music: some View {
        Form {
            Section {
                Toggle("Musik in der Insel anzeigen", isOn: $settings.showMusic)
            }
            Section("Quellen") {
                Toggle("Apple Music", isOn: $settings.sourceAppleMusic)
                Toggle("Spotify", isOn: $settings.sourceSpotify)
                Toggle("eSound", isOn: $settings.sourceESound)
            }
            .disabled(!settings.showMusic)
            Section("Anzeige") {
                Toggle("Equalizer neben der Notch", isOn: $settings.showEqualizer)
                Toggle("Lyrics", isOn: $settings.showLyrics)
                SliderRow(title: "Lyrics-Versatz", value: $settings.lyricsOffset, range: -3...3, step: 0.1, unit: "s", signed: true)
                    .disabled(!settings.showLyrics)
                Text("Kommen die Lyrics zu spät, den Wert erhöhen – kommen sie zu früh, verringern.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!settings.showMusic)
        }
        .formStyle(.grouped)
    }

    private var look: some View {
        Form {
            Section("Liquid Glass") {
                Toggle("Glas-Optik beim Ausklappen", isOn: $settings.liquidGlass)
                SliderRow(title: "Abdunkelung", value: $settings.glassDarkness, range: 0...0.9, step: 0.05, unit: "%", percent: true)
                    .disabled(!settings.liquidGlass)
            }
            Section("Farbe") {
                Picker("Akzentfarbe", selection: $settings.accentFromCover) {
                    Text("Aus dem Cover").tag(true)
                    Text("Eigene Farbe").tag(false)
                }
                ColorPicker("Eigene Farbe", selection: $settings.fixedAccent, supportsOpacity: false)
                    .disabled(settings.accentFromCover)
            }
            Section("Fortschrittsbalken") {
                SliderRow(title: "Dicke", value: $settings.barThickness, range: 3...12, step: 1, unit: "px")
            }
        }
        .formStyle(.grouped)
    }

    private var weather: some View {
        Form {
            Section {
                Toggle("Wetter oben rechts anzeigen", isOn: $settings.showWeather)
            }
            Section("Ort") {
                HStack {
                    TextField("Stadt", text: $settings.city, prompt: Text("leer = aktueller Standort"))
                        .onSubmit(applyCity)
                    Button("Übernehmen", action: applyCity)
                }
            }
            .disabled(!settings.showWeather)
            Section("Einheit") {
                Picker("Temperatur", selection: $settings.fahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
            }
            .disabled(!settings.showWeather)
        }
        .formStyle(.grouped)
    }

    private func applyCity() {
        let city = settings.city.trimmingCharacters(in: .whitespaces)
        settings.city = city
        ui.weather.setCity(city.isEmpty ? nil : city)
    }
}

/// Schieberegler mit Titel und aktuellem Wert.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var signed = false
    var percent = false

    var body: some View {
        HStack {
            Text(title)
            // Ohne `step:` – sonst zeichnet macOS für jeden Schritt einen Strich. Gerundet wird hier.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
            Text(label).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
    }

    private var label: String {
        if percent { return "\(Int((value * 100).rounded())) %" }
        if unit == "px" { return "\(Int(value)) px" }
        return (signed && value > 0 ? "+" : "") + String(format: "%.2g", value) + " \(unit)"
    }
}
