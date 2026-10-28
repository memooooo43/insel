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

// MARK: - Fenster (aufgebaut wie die macOS-Systemeinstellungen)

final class SettingsWindow {
    private static var window: NSWindow?

    static func show(ui: IslandUI) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(ui: ui, settings: .shared)))
            w.title = "Insel"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPane: Int, CaseIterable, Identifiable {
    case general, music, look, weather, about
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "Allgemein"
        case .music: return "Musik"
        case .look: return "Aussehen"
        case .weather: return "Wetter"
        case .about: return "Info"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .music: return "music.note"
        case .look: return "paintpalette.fill"
        case .weather: return "cloud.sun.fill"
        case .about: return "info.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: return [Color(white: 0.6), Color(white: 0.42)]
        case .music: return [Color(red: 1, green: 0.38, blue: 0.45), Color(red: 0.92, green: 0.2, blue: 0.32)]
        case .look: return [Color(red: 0.55, green: 0.45, blue: 1), Color(red: 0.35, green: 0.3, blue: 0.9)]
        case .weather: return [Color(red: 0.35, green: 0.75, blue: 1), Color(red: 0.15, green: 0.5, blue: 0.95)]
        case .about: return [Color(red: 0.3, green: 0.6, blue: 1), Color(red: 0.15, green: 0.4, blue: 0.9)]
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Starten beim Login, wie schnell die Insel auf- und zuklappt und welche Funktionen sie hat."
        case .music: return "Welche Player die Insel anzeigt, Equalizer und Lyrics."
        case .look: return "Liquid Glass, Akzentfarbe und Fortschrittsbalken."
        case .weather: return "Ort und Einheit für die Wetteranzeige oben rechts."
        case .about: return "Version, Quellcode und Zurücksetzen."
        }
    }
}

/// Farbiges Symbol wie in den Systemeinstellungen.
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: pane.colors, startPoint: .top, endPoint: .bottom)))
    }
}

/// Gewählte Seite (eigene Klasse statt @State, siehe IslandUI).
final class SettingsTab: ObservableObject {
    @Published var selected: SettingsPane? = .general
    init(_ pane: SettingsPane = .general) { selected = pane }
}

struct SettingsView: View {
    let ui: IslandUI
    @ObservedObject var settings: Settings
    @ObservedObject var tab = SettingsTab()

    var body: some View {
        NavigationSplitView {
            List(selection: $tab.selected) {
                // Kopf wie das Apple-Konto in den Systemeinstellungen
                HStack(spacing: 10) {
                    Image(systemName: "capsule.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(LinearGradient(colors: [Color(white: 0.25), .black], startPoint: .top, endPoint: .bottom)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Insel").font(.headline)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .selectionDisabled()

                ForEach(SettingsPane.allCases) { pane in
                    Label { Text(pane.title) } icon: { PaneIcon(pane: pane) }
                        .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = tab.selected ?? .general
            Form {
                Section {
                    VStack(spacing: 8) {
                        PaneIcon(pane: pane, size: 56)
                        Text(pane.title).font(.title2.bold())
                        Text(pane.subtitle)
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                content(for: pane)
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(width: 740, height: 540)
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: general
        case .music: music
        case .look: look
        case .weather: weather
        case .about: about
        }
    }

    @ViewBuilder private var general: some View {
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
        }
        Section {
            LabeledContent("Dateien in der Ablage") {
                Button("Ablage leeren") { ui.tray.clear() }
            }
        }
    }

    @ViewBuilder private var music: some View {
        Section {
            Toggle("Musik in der Insel anzeigen", isOn: $settings.showMusic)
        }
        Section("Quellen") {
            Toggle("Apple Music", isOn: $settings.sourceAppleMusic)
            Toggle("Spotify", isOn: $settings.sourceSpotify)
            Toggle("eSound", isOn: $settings.sourceESound)
        }
        .disabled(!settings.showMusic)
        Section {
            Toggle("Equalizer neben der Notch", isOn: $settings.showEqualizer)
            Toggle("Lyrics", isOn: $settings.showLyrics)
            SliderRow(title: "Lyrics-Versatz", value: $settings.lyricsOffset, range: -3...3, step: 0.1, unit: "s", signed: true)
                .disabled(!settings.showLyrics)
        } header: {
            Text("Anzeige")
        } footer: {
            Text("Lyrics kommen von eSound selbst oder von LRCLIB. Kommen sie zu spät, den Versatz erhöhen – zu früh, verringern.")
        }
        .disabled(!settings.showMusic)
    }

    @ViewBuilder private var look: some View {
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

    @ViewBuilder private var weather: some View {
        Section {
            Toggle("Wetter oben rechts anzeigen", isOn: $settings.showWeather)
        }
        Section {
            HStack {
                TextField("Stadt", text: $settings.city, prompt: Text("leer = aktueller Standort"))
                    .onSubmit(applyCity)
                Button("Übernehmen", action: applyCity)
            }
            Picker("Temperatur", selection: $settings.fahrenheit) {
                Text("°C").tag(false)
                Text("°F").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Ort & Einheit")
        } footer: {
            Text("Wetterdaten von Open-Meteo – kostenlos und ohne Account.")
        }
        .disabled(!settings.showWeather)
    }

    @ViewBuilder private var about: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            LabeledContent("Quellcode") {
                Link("github.com/memooooo43/insel", destination: URL(string: "https://github.com/memooooo43/insel")!)
            }
            LabeledContent("Gebaut mit", value: "Claude Code")
        }
        Section {
            LabeledContent("Alle Einstellungen") {
                Button("Zurücksetzen") { settings.reset() }
            }
            LabeledContent("Insel") {
                Button("Beenden") { NSApp.terminate(nil) }
            }
        }
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
