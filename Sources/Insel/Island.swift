import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

/// Liquid Glass lässt sich nicht in Vorschaubilder rendern – `--snapshot` schaltet es ab.
var glassEnabled = true

/// Glas nur, wenn es renderbar ist und in den Einstellungen eingeschaltet.
var useGlass: Bool { glassEnabled && Settings.shared.liquidGlass }

/// Notch-Form: oben zwei kleine nach außen gebogene Ausläufer, unten runde Ecken.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let radius = min(radius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + flare, y: r.minY + flare), control: CGPoint(x: r.minX + flare, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + flare, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + flare + radius, y: r.maxY), control: CGPoint(x: r.minX + flare, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - flare - radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - flare, y: r.maxY - radius), control: CGPoint(x: r.maxX - flare, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - flare, y: r.minY + flare))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - flare, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var ui: IslandUI

    var body: some View {
        let size = ui.size
        let flare = ui.expanded ? IslandUI.flareExpanded : IslandUI.flareCollapsed
        ZStack(alignment: .top) {
            IslandBackground(expanded: ui.expanded, flare: flare, notchHeight: ui.notch.height, height: size.height)
                .shadow(color: .black.opacity(ui.expanded ? 0.4 : 0), radius: 20, y: 10)
                .opacity(!ui.hasNotch && ui.isIdle ? 0 : 1)

            Group {
                if ui.expanded {
                    ExpandedView(ui: ui, music: ui.music, tray: ui.tray)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.08)),
                                                removal: .opacity.animation(.easeIn(duration: 0.1))))
                } else if let event = ui.event {
                    CompactSides(notch: ui.notch, flare: flare) {
                        Image(systemName: event.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(event.color)
                    } right: {
                        Text(event.value).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(event.color)
                    }
                    .transition(.opacity)
                } else if ui.music.isActive {
                    CompactMusic(music: ui.music, notch: ui.notch, flare: flare)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(NotchShape(flare: flare, radius: 11))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard Settings.shared.showTray else { return false }
            ui.tray.add(providers)
            ui.tab = .tray
            return true
        }
        .contextMenu {
            Button("Einstellungen …") { SettingsWindow.show(ui: ui) }
            Button("Ablage leeren") { ui.tray.clear() }
            Divider()
            Button("Insel beenden") { NSApp.terminate(nil) }
        }
        .animation(spring, value: size)
        .animation(spring, value: ui.event)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Eingeklappt pures Schwarz (verschmilzt mit der Notch). Ausgeklappt Liquid Glass:
/// oben bleibt es schwarz, damit der Übergang zur echten Notch unsichtbar ist, nach unten wird es gläsern.
struct IslandBackground: View {
    let expanded: Bool
    let flare: CGFloat
    let notchHeight: CGFloat
    let height: CGFloat

    var body: some View {
        let shape = NotchShape(flare: flare, radius: expanded ? 32 : 11)
        let notchEnd = min(notchHeight / max(height, 1), 0.9)
        let darkness = Settings.shared.glassDarkness
        ZStack {
            if useGlass, #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(.black.opacity(darkness)), in: shape)
                    .opacity(expanded ? 1 : 0)
            } else if expanded {
                // Ohne Glas: in der Vorschau grau, wenn abgeschaltet schwarz
                shape.fill(glassEnabled ? Color.black : Color(white: 0.16))
            }
            shape.fill(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: notchEnd),
                .init(color: .black.opacity(expanded ? min(darkness + 0.25, 1) : 1), location: min(notchEnd + 0.3, 1)),
                .init(color: .black.opacity(expanded ? min(darkness + 0.1, 1) : 1), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            // Feine Lichtkante unten, wie bei Glas
            shape.stroke(LinearGradient(colors: [.clear, .clear, .white.opacity(expanded ? 0.22 : 0)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

// MARK: - Eingeklappt

/// Inhalt links und rechts neben der echten Notch.
struct CompactSides<L: View, R: View>: View {
    let notch: CGSize
    let flare: CGFloat
    @ViewBuilder let left: L
    @ViewBuilder let right: R

    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notch.width)
            right.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, flare + 10)
        .frame(height: notch.height)
    }
}

struct CompactMusic: View {
    @ObservedObject var music: MusicModel
    let notch: CGSize
    let flare: CGFloat

    var body: some View {
        CompactSides(notch: notch, flare: flare) {
            Artwork(image: music.artwork, size: 22, corner: 6)
        } right: {
            if Settings.shared.showEqualizer {
                Equalizer(color: music.accent, playing: music.playing)
            }
        }
    }
}

/// Equalizer-Balken als Core-Animation-Ebenen: macOS animiert sie selbst,
/// die App muss dafür nicht jedes Bild neu berechnen (SwiftUI-Version kostete ~5 % CPU).
struct Equalizer: NSViewRepresentable {
    let color: Color
    let playing: Bool

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }
    func updateNSView(_ view: EqualizerView, context: Context) { view.update(color: NSColor(color), playing: playing) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? {
        CGSize(width: 18, height: 14)
    }
}

final class EqualizerView: NSView {
    private var bars: [CALayer] = []
    private var isPlaying: Bool?
    private static let durations = [0.42, 0.31, 0.5, 0.37]

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 14))
        wantsLayer = true
        for _ in 0..<4 {
            let bar = CALayer()
            bar.cornerRadius = 1.5
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * 5 + 1.5, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func update(color: NSColor, playing: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        guard playing != isPlaying else { return }
        isPlaying = playing
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.transform = CATransform3DMakeScale(1, playing ? 1 : 0.25, 1)
            guard playing else { continue }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.25
            a.toValue = 1.0
            a.duration = Self.durations[i]
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timeOffset = Double(i) * 0.13
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(a, forKey: "eq")
        }
    }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Ausgeklappt

struct ExpandedView: View {
    @ObservedObject var ui: IslandUI
    @ObservedObject var music: MusicModel
    @ObservedObject var tray: TrayModel
    @ObservedObject var settings = Settings.shared

    /// Gewählter Tab – fällt auf den anderen zurück, wenn einer ausgeschaltet ist.
    private var tab: IslandUI.Tab? {
        let available = [settings.showMusic ? IslandUI.Tab.music : nil, settings.showTray ? .tray : nil].compactMap { $0 }
        return available.contains(ui.tab) ? ui.tab : available.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kopfzeile links/rechts neben der Notch
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    if settings.showMusic {
                        TabButton(symbol: "music.note", active: tab == .music) { ui.tab = .music }
                    }
                    if settings.showTray {
                        TabButton(symbol: tray.files.isEmpty ? "tray" : "tray.full", active: tab == .tray) { ui.tab = .tray }
                    }
                    TabButton(symbol: "gearshape", active: false) { SettingsWindow.show(ui: ui) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: ui.notch.width)
                HStack(spacing: 12) {
                    WeatherLabel(weather: ui.weather)
                    BatteryLabel(battery: ui.battery)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(ui.notch.height, 30))

            Group {
                switch tab {
                case .music: MusicPanel(music: music)
                case .tray: TrayPanel(tray: tray)
                case nil:
                    Text("Musik und Ablage sind in den Einstellungen ausgeschaltet.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, IslandUI.flareExpanded + 22)
        .foregroundStyle(.white)
    }
}

struct GlassCapsule: View {
    var body: some View {
        if useGlass, #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.white.opacity(0.08)), in: Capsule())
        } else {
            Capsule().fill(.white.opacity(0.16))
        }
    }
}

struct GlassCircle: View {
    let size: CGFloat

    var body: some View {
        Group {
            if useGlass, #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(.white.opacity(0.06)).interactive(), in: Circle())
            } else {
                Circle().fill(.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
    }
}

struct TabButton: View {
    let symbol: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : 0.45))
                .frame(width: 30, height: 22)
                .background { if active { GlassCapsule() } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct WeatherLabel: View {
    @ObservedObject var weather: WeatherModel
    @ObservedObject var settings = Settings.shared

    var body: some View {
        if settings.showWeather, let c = weather.temperature {
            let t = settings.fahrenheit ? Int((Double(c) * 9 / 5 + 32).rounded()) : c
            HStack(spacing: 4) {
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 12))
                Text("\(t)°").font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .onTapGesture { openApp(bundleID: "com.apple.weather") }
        }
    }
}

struct BatteryLabel: View {
    @ObservedObject var battery: BatteryModel
    @ObservedObject var settings = Settings.shared

    var body: some View {
        if settings.showBattery, battery.hasBattery {
            HStack(spacing: 4) {
                Text("\(battery.level) %").font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: battery.symbol).font(.system(size: 14)).foregroundStyle(battery.color)
            }
        }
    }
}

struct MusicPanel: View {
    @ObservedObject var music: MusicModel

    var body: some View {
        if music.player == nil {
            VStack(spacing: 10) {
                Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                Text("Gerade läuft nichts").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Button("Musik öffnen") { music.playPause() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.14)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Artwork(image: music.artwork, size: 62, corner: 14)
                            .shadow(color: music.accent.opacity(0.35), radius: 10)
                            .onTapGesture { music.openPlayer() }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(music.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(music.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 18) {
                            Control(symbol: "backward.fill", size: 15) { music.previous() }
                            Control(symbol: music.playing ? "pause.fill" : "play.fill", size: 20) { music.playPause() }
                                .background(GlassCircle(size: 44))
                            Control(symbol: "forward.fill", size: 15) { music.next() }
                        }
                    }
                    Progress(music: music, position: music.position(at: ctx.date))
                    if Settings.shared.showLyrics {
                        Lyrics(music: music, date: ctx.date)
                    }
                }
            }
        }
    }
}

struct Control: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Zustand des Balkens (Hover/Ziehen). @State ist im SDK ein Makro, das die Command Line Tools nicht haben.
final class ScrubState: ObservableObject {
    @Published var hovering = false
    @Published var dragFraction: Double?
}

struct Progress: View {
    let music: MusicModel
    let position: Double
    @StateObject private var scrub = ScrubState()

    var body: some View {
        let live = music.duration > 0 ? min(1, position / music.duration) : 0
        let fraction = scrub.dragFraction ?? live
        let active = scrub.hovering || scrub.dragFraction != nil
        let base = CGFloat(Settings.shared.barThickness)
        let thickness: CGFloat = active ? base + 4 : base
        HStack(spacing: 10) {
            Text(Self.time(fraction * music.duration)).frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                let clamp = { (x: CGFloat) in min(max(Double(x / geo.size.width), 0), 1) }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(LinearGradient(colors: [music.accent.opacity(0.7), music.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(thickness, geo.size.width * fraction))
                        .shadow(color: music.accent.opacity(active ? 0.6 : 0.35), radius: active ? 8 : 4)
                }
                .frame(height: thickness)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { scrub.hovering = h } }
                // Ziehen zeigt die Stelle live, gesprungen wird beim Loslassen
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.85)) { scrub.dragFraction = clamp(v.location.x) }
                    }
                    .onEnded { v in
                        music.seek(to: clamp(v.location.x))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { scrub.dragFraction = nil }
                    })
            }
            .frame(height: 18)
            // Gleitet zwischen den Aktualisierungen (alle 0,25 s) gleichmäßig weiter statt zu springen
            .animation(scrub.dragFraction == nil ? .linear(duration: 0.25) : nil, value: live)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
            Text("-" + Self.time(max(0, music.duration - fraction * music.duration))).frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
    }

    static func time(_ s: Double) -> String {
        let s = Int(s.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct Lyrics: View {
    let music: MusicModel
    let date: Date

    var body: some View {
        Group {
            switch music.lyrics {
            case .loaded(let lines):
                LyricsScroller(lines: lines, index: music.lyricIndex(at: date), accent: music.accent, synced: music.lyricsSynced)
            case .loading:
                hint("Lyrics werden geladen …")
            case .notFound:
                hint("Keine Lyrics gefunden")
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: LyricsScroller.lineHeight * 2, alignment: .topLeading)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
    }
}

/// Alle Zeilen untereinander; beim Zeilenwechsel gleitet die Liste mit einer Feder nach oben
/// (wie bei Apple Music). Die aktive Zeile ist groß und farbig, die anderen klein und blass.
struct LyricsScroller: View {
    let lines: [LyricLine]
    let index: Int
    let accent: Color
    let synced: Bool

    static let lineHeight: CGFloat = 21

    var body: some View {
        // Nur die Zeilen rund um die aktuelle zeichnen (statt aller 60+), jede an ihrer Stelle
        let visible = max(index - 1, 0)...max(min(index + 3, lines.count - 1), 0)
        ZStack(alignment: .topLeading) {
            ForEach(Array(visible), id: \.self) { i in
                let active = i == index
                Text(lines[i].text)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(active ? accent : .white.opacity(i < index ? 0.2 : 0.42))
                    .scaleEffect(active ? 1 : 0.84, anchor: .leading)
                    .frame(maxWidth: .infinity, minHeight: Self.lineHeight, maxHeight: Self.lineHeight, alignment: .leading)
                    // Aktive Zeile steht oben, die nächste darunter
                    .offset(y: CGFloat(i - index) * Self.lineHeight)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: index)
        .frame(maxWidth: .infinity, maxHeight: Self.lineHeight * 2, alignment: .topLeading)
        .clipped()
        // Oben und unten weich ausblenden statt hart abschneiden
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
            .init(color: .black, location: 0.8), .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .topTrailing) {
            if !synced {
                Text("≈ nicht synchron").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

struct TrayPanel: View {
    @ObservedObject var tray: TrayModel

    var body: some View {
        if tray.files.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 22))
                Text("Dateien hierher ziehen").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tray.files, id: \.self) { url in TrayItem(url: url, tray: tray) }
                    }
                }
                HStack {
                    Text("\(tray.files.count) \(tray.files.count == 1 ? "Datei" : "Dateien") · rausziehen zum Ablegen")
                    Spacer()
                    Button("Leeren") { withAnimation { tray.clear() } }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct TrayItem: View {
    let url: URL
    let tray: TrayModel

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Öffnen") { NSWorkspace.shared.open(url) }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Aus Ablage entfernen") { withAnimation { tray.remove(url) } }
        }
        .help(url.path)
    }
}
