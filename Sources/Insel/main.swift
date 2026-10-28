import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Zustand der Insel. (@State ist im aktuellen SDK ein Makro, das die Command Line Tools nicht mitliefern –
/// deshalb liegt aller UI-Zustand hier.)
final class IslandUI: ObservableObject {
    enum Tab { case music, tray }

    @Published var expanded = false
    @Published var tab = Tab.music
    @Published var event: IslandEvent?
    @Published var notch = CGSize(width: 200, height: 32)
    @Published var hasNotch = true

    let music = MusicModel()
    let battery = BatteryModel()
    let airpods = AirPodsModel()
    let weather = WeatherModel()
    let tray = TrayModel()
    private var bag: [AnyCancellable] = []

    static let expandedSize = CGSize(width: 620, height: 196)
    static let flareCollapsed: CGFloat = 7
    static let flareExpanded: CGFloat = 14

    init() {
        for model in [music.objectWillChange, tray.objectWillChange] as [ObservableObjectPublisher] {
            bag.append(model.sink { [weak self] in self?.objectWillChange.send() })
        }
        // Einstellungen ändern Größe, Farben und Inhalte – alle Ansichten neu zeichnen
        bag.append(Settings.shared.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
            self?.music.objectWillChange.send()
        })
        battery.onPluggedIn = { [weak self] in
            guard let self, Settings.shared.notifyCharging else { return }
            self.show(IslandEvent(icon: "bolt.fill", value: "\(self.battery.level) %", color: .green))
        }
        airpods.onConnect = { [weak self] d in
            guard Settings.shared.notifyAirPods else { return }
            self?.show(IslandEvent(icon: d.icon, value: d.lowest.map { "\($0) %" } ?? "", color: .white))
        }
    }

    var isIdle: Bool { !expanded && event == nil && !music.isActive }

    /// Sichtbare Größe der Insel, inklusive der kleinen Ausläufer oben links/rechts.
    var size: CGSize {
        if expanded { return Self.expandedSize }
        let base = notch.width + 2 * Self.flareCollapsed
        if event != nil { return CGSize(width: base + 150, height: notch.height) }
        if music.isActive { return CGSize(width: base + 84, height: notch.height) }
        return hasNotch ? CGSize(width: base, height: notch.height) : CGSize(width: 220, height: 6)
    }

    func show(_ e: IslandEvent) {
        event = e
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.event?.id == e.id { self?.event = nil }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ui = IslandUI()
    private var panel: IslandPanel!
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var draggingFiles = false
    private var dragChangeCount: Int?

    private static let panelSize = CGSize(width: 720, height: 250)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-settings"), i + 1 < CommandLine.arguments.count {
            snapshotSettings(to: CommandLine.arguments[i + 1])
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            return
        }
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IslandView(ui: ui))
        place()
        panel.orderFrontRegardless()

        // Mausposition abfragen statt auf Events zu warten: Über dem (nie aktiven) Panel
        // kommen Mausbewegungen sonst nicht zuverlässig an.
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(timer, forMode: .common)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.place() }
    }

    /// `Insel --snapshot <datei.png>`: alle Zustände mit Beispieldaten als Bild rendern.
    private func snapshot(to url: URL) {
        glassEnabled = false
        demoMode = true
        place(updatePanel: false)
        let states: [(IslandUI) -> Void] = [
            { _ in },
            { $0.music.loadDemo() },
            { $0.event = IslandEvent(icon: "bolt.fill", value: "\($0.battery.level) %", color: .green) },
            { $0.music.loadDemo(); $0.expanded = true },
            { ui in
                ui.expanded = true; ui.tab = .tray
                ["/Applications/Safari.app", "/System/Library/CoreServices/Finder.app", "/etc/hosts"].forEach { ui.tray.add(URL(fileURLWithPath: $0)) }
            },
        ]
        let rows = states.map { configure -> AnyView in
            let ui = IslandUI()
            ui.notch = self.ui.notch
            ui.hasNotch = true
            configure(ui)
            return AnyView(IslandView(ui: ui).frame(width: 720, height: ui.expanded ? 220 : 50))
        }
        let root = VStack(spacing: 14) { ForEach(0..<rows.count, id: \.self) { rows[$0] } }
            .padding(20)
            .background(LinearGradient(colors: [Color(red: 0.75, green: 0.8, blue: 0.9), Color(red: 0.45, green: 0.5, blue: 0.65)], startPoint: .top, endPoint: .bottom))
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.setContentSize(view.fittingSize)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            exit(0)
        }
    }

    /// `Insel --snapshot-settings <ordner>`: alle Seiten des Einstellungsfensters als Bilder.
    private func snapshotSettings(to folder: String) {
        demoMode = true
        var windows: [NSWindow] = []
        for pane in SettingsPane.allCases {
            let view = NSHostingView(rootView: SettingsView(ui: ui, settings: .shared, tab: SettingsTab(pane)))
            let w = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 740, height: 540), styleMask: .titled, backing: .buffered, defer: false)
            w.contentView = view
            w.orderFrontRegardless()
            windows.append(w)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (i, w) in windows.enumerated() {
                guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/einstellungen-\(i).png"))
            }
            exit(0)
        }
    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first!
    }

    private func place(updatePanel: Bool = true) {
        let s = screen
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            ui.notch = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
            ui.hasNotch = true
        } else {
            ui.notch = CGSize(width: 190, height: NSStatusBar.system.thickness + 6)
            ui.hasNotch = false
        }
        guard updatePanel else { return }
        let size = Self.panelSize
        panel.setFrame(NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Das Panel ist größer als die Insel. Damit die Menüleiste klickbar bleibt, lässt es Klicks
    /// nur innerhalb der Insel zu – und öffnet/schließt sie beim Hovern.
    private func track() {
        let p = NSEvent.mouseLocation
        let f = screen.frame
        let s = ui.size
        // Nach oben über die Bildschirmkante hinaus verlängert: Die oberste Pixelreihe hat y == maxY
        // und läge sonst knapp außerhalb – genau dort landet die Maus, wenn man sie an die Notch schiebt.
        let margin: CGFloat = ui.expanded ? 10 : 6
        let rect = NSRect(x: f.midX - s.width / 2 - margin, y: f.maxY - s.height - margin,
                          width: s.width + 2 * margin, height: s.height + margin + 20)
        let dropZone = NSRect(x: f.midX - 220, y: f.maxY - 100, width: 440, height: 120)

        // Datei-Drag erkennen: Maustaste gedrückt und seit dem Drücken neuer Inhalt auf dem Drag-Pasteboard.
        // Das Pasteboard nur bei gedrückter Taste abfragen – jede Abfrage ist ein Aufruf an einen Systemdienst.
        if NSEvent.pressedMouseButtons & 1 == 0 {
            dragChangeCount = nil
            draggingFiles = false
        } else if !draggingFiles {
            let pasteboard = NSPasteboard(name: .drag)
            if dragChangeCount == nil {
                dragChangeCount = pasteboard.changeCount
            } else if pasteboard.changeCount != dragChangeCount, dropZone.contains(p),
                      Settings.shared.showTray, pasteboard.types?.contains(.fileURL) == true {
                draggingFiles = true
                ui.tab = .tray
            }
        }

        let inside = rect.contains(p) || (draggingFiles && dropZone.contains(p))
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if inside {
            collapseWork?.cancel(); collapseWork = nil
            guard !ui.expanded, expandWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.expandWork = nil
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { self?.ui.expanded = true }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (draggingFiles ? 0 : Settings.shared.openDelay), execute: work)
        } else {
            expandWork?.cancel(); expandWork = nil
            guard ui.expanded, collapseWork == nil, !draggingFiles else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.collapseWork = nil
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { self?.ui.expanded = false }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Settings.shared.closeDelay, execute: work)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
