import AudioToolbox
import CoreAudio
import Foundation

/// Sanfte Übergänge für eSound, das selbst nicht überblenden kann: in den letzten Sekunden eines
/// Songs die Mac-Lautstärke herunterfahren, beim nächsten Song wieder hoch. An den Ton von eSound
/// allein kommt die Insel nicht heran – deshalb die Lautstärke des ganzen Macs.
final class TransitionFader {
    /// Auf diesen Anteil der Lautstärke wird am Song-Ende ausgeblendet (nicht ganz stumm).
    static let floor: Float = 0.2
    static let fadeInSeconds = 1.5

    private let getVolume: () -> Float?
    private let setVolume: (Float) -> Void

    /// Lautstärke vor dem Ausblenden – solange gesetzt, ist ein Übergang im Gange.
    private(set) var original: Float?
    private var lastSet: Float?
    private var track = ""
    private var fadeIn: (from: Float, at: Date)?
    private var endedAt: Date?

    init(getVolume: @escaping () -> Float? = SystemVolume.get, setVolume: @escaping (Float) -> Void = SystemVolume.set) {
        self.getVolume = getVolume
        self.setVolume = setVolume
    }

    /// Wird ~20× pro Sekunde aufgerufen.
    func tick(enabled: Bool, playing: Bool, track: String, remaining: Double, fadeSeconds: Double, duration: Double, now: Date = Date()) {
        guard enabled else { restore(); return }

        // Lautstärke selbst verändert? Dann nicht dagegen arbeiten.
        if let lastSet, let current = getVolume(), abs(current - lastSet) > 0.03 {
            original = nil; self.lastSet = nil; fadeIn = nil
            return
        }

        if let o = original, let f = fadeIn {
            // Neuer Song läuft: wieder hochfahren
            let progress = min(now.timeIntervalSince(f.at) / Self.fadeInSeconds, 1)
            apply(f.from + (o - f.from) * Float(progress))
            if progress >= 1 { original = nil; lastSet = nil; fadeIn = nil }
            return
        }

        if let o = original {
            if track != self.track {
                fadeIn = (lastSet ?? o * Self.floor, now)        // Song gewechselt
            } else if !playing || remaining > fadeSeconds + 0.5 {
                restore()                                        // pausiert oder zurückgespult
            } else if remaining <= 0 {
                // Song zu Ende, aber kein neuer (Ende der Playlist) – nach 3 s zurückstellen
                if endedAt == nil { endedAt = now }
                if now.timeIntervalSince(endedAt!) > 3 { restore() }
            } else {
                apply(o * (Self.floor + (1 - Self.floor) * Float(remaining / fadeSeconds)))
            }
            return
        }

        // Ausblenden beginnen – nicht bei sehr kurzen Songs
        if playing, duration > fadeSeconds * 3, remaining > 0, remaining <= fadeSeconds, let current = getVolume(), current > 0.01 {
            original = current
            self.track = track
            endedAt = nil
            apply(current * (Self.floor + (1 - Self.floor) * Float(remaining / fadeSeconds)))
        }
    }

    /// Ursprüngliche Lautstärke sofort wiederherstellen (Pause, Beenden, ausgeschaltet).
    func restore() {
        guard let o = original else { return }
        setVolume(o)
        original = nil; lastSet = nil; fadeIn = nil; endedAt = nil
    }

    private func apply(_ v: Float) {
        let clamped = min(max(v, 0), 1)
        setVolume(clamped)
        lastSet = clamped
    }
}

/// Lautstärke des Standard-Ausgabegeräts (0…1) über CoreAudio – ohne Rückfrage.
enum SystemVolume {
    private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static func device() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    static func get() -> Float? {
        guard let id = device() else { return nil }
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func set(_ value: Float) {
        guard let id = device() else { return }
        var v = Float32(value)
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }
}
