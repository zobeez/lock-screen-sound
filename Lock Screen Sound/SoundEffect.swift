import Foundation

/// The sound effects the user can choose to play when the phone locks.
///
/// There are three kinds of sound:
/// - Synthesized tones, generated into 16-bit PCM WAV data at runtime.
/// - Bundled royalty-free MP3 effects shipped inside the app.
/// - A `custom` sound imported by the user; its audio data is supplied by
///   `LockMonitor` rather than by this enum.
enum SoundEffect: Identifiable, Hashable {
    // Synthesized tones
    case beep
    case chime
    case coin
    case descending
    case alarm

    // Bundled royalty-free effects
    case levelUp
    case twinkle
    case success

    // A sound the user imported from their own MP3 file, identified by its id
    case custom(UUID)

    /// The built-in sounds, in the order they appear in the picker. `custom`
    /// is excluded because it only exists once the user imports a file.
    static let builtInCases: [SoundEffect] = [
        .beep, .chime, .coin, .descending, .alarm,
        .levelUp, .twinkle, .success
    ]

    var id: String {
        switch self {
        case .beep: return "beep"
        case .chime: return "chime"
        case .coin: return "coin"
        case .descending: return "descending"
        case .alarm: return "alarm"
        case .levelUp: return "levelUp"
        case .twinkle: return "twinkle"
        case .success: return "success"
        case .custom(let uuid): return "custom-\(uuid.uuidString)"
        }
    }

    init?(id: String) {
        if id.hasPrefix("custom-") {
            guard let uuid = UUID(uuidString: String(id.dropFirst("custom-".count))) else { return nil }
            self = .custom(uuid)
            return
        }
        guard let match = SoundEffect.builtInCases.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    /// The name shown in the picker. For `custom`, `LockMonitor` shows the
    /// imported file's name instead of this fallback.
    var displayName: String {
        switch self {
        case .beep: return "Beep"
        case .chime: return "Chime"
        case .coin: return "Coin"
        case .descending: return "Power Down"
        case .alarm: return "Alarm"
        case .levelUp: return "Level Up"
        case .twinkle: return "Twinkle"
        case .success: return "Success"
        case .custom: return "Custom Sound"
        }
    }

    /// A short human-readable description shown in the UI.
    var subtitle: String {
        switch self {
        case .beep: return "A single clean tone"
        case .chime: return "A rising three-note chime"
        case .coin: return "A quick two-note blip"
        case .descending: return "A descending power-down"
        case .alarm: return "An alternating alarm buzz"
        case .levelUp: return "A cheerful level-up flourish"
        case .twinkle: return "A twinkling notification chime"
        case .success: return "A bright positive chime"
        case .custom: return "Your imported MP3"
        }
    }

    /// An SF Symbol representing the effect, shown in the picker.
    var systemImage: String {
        switch self {
        case .beep: return "dot.radiowaves.left.and.right"
        case .chime: return "bell.fill"
        case .coin: return "centsign.circle.fill"
        case .descending: return "arrow.down.right.circle.fill"
        case .alarm: return "alarm.fill"
        case .levelUp: return "arrow.up.forward.circle.fill"
        case .twinkle: return "sparkles"
        case .success: return "checkmark.seal.fill"
        case .custom: return "waveform.circle.fill"
        }
    }

    /// The base filename (without extension) of a bundled MP3, if this effect
    /// is one of the shipped royalty-free sounds.
    private var bundledResourceName: String? {
        switch self {
        case .levelUp: return "LevelUp"
        case .twinkle: return "Twinkle"
        case .success: return "Success"
        default: return nil
        }
    }

    /// Ready-to-play audio data for the built-in sounds (synthesized tones and
    /// bundled MP3s). Returns `nil` for `custom`, whose data is provided by
    /// `LockMonitor`.
    var builtInAudioData: Data? {
        if let name = bundledResourceName {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
            return try? Data(contentsOf: url)
        }
        if case .custom = self { return nil }
        return synthesizedWAV
    }

    /// WAV data for the synthesized tones.
    private var synthesizedWAV: Data {
        var samples: [Int16] = []
        switch self {
        case .beep:
            samples += AudioSynth.tone(frequency: 880, duration: 0.30)
        case .chime:
            samples += AudioSynth.tone(frequency: 523.25, duration: 0.16) // C5
            samples += AudioSynth.tone(frequency: 659.25, duration: 0.16) // E5
            samples += AudioSynth.tone(frequency: 783.99, duration: 0.28) // G5
        case .coin:
            samples += AudioSynth.tone(frequency: 987.77, duration: 0.09)  // B5
            samples += AudioSynth.tone(frequency: 1318.51, duration: 0.30) // E6
        case .descending:
            samples += AudioSynth.tone(frequency: 783.99, duration: 0.14)
            samples += AudioSynth.tone(frequency: 659.25, duration: 0.14)
            samples += AudioSynth.tone(frequency: 523.25, duration: 0.14)
            samples += AudioSynth.tone(frequency: 392.00, duration: 0.30)
        case .alarm:
            for _ in 0..<4 {
                samples += AudioSynth.tone(frequency: 1000, duration: 0.12)
                samples += AudioSynth.tone(frequency: 800, duration: 0.12)
            }
        default:
            break
        }
        return AudioSynth.makeWAV(samples: samples)
    }
}

/// Small helper that synthesizes tones and packs them into WAV containers.
enum AudioSynth {
    static let sampleRate = 44_100

    /// Generates a sine-wave tone with short fade in/out to avoid clicks.
    static func tone(frequency: Double, duration: Double, amplitude: Double = 0.6) -> [Int16] {
        let frameCount = Int(duration * Double(sampleRate))
        guard frameCount > 0 else { return [] }

        let fade = min(frameCount / 8, 441) // up to ~10ms fade
        var samples = [Int16](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / Double(sampleRate)
            var value = sin(2.0 * .pi * frequency * t) * amplitude

            // Envelope to prevent audible pops at note boundaries.
            if i < fade {
                value *= Double(i) / Double(fade)
            } else if i > frameCount - fade {
                value *= Double(frameCount - i) / Double(fade)
            }

            samples[i] = Int16(max(-1.0, min(1.0, value)) * Double(Int16.max))
        }
        return samples
    }

    /// One second of digital silence, used for the background keep-alive loop.
    static func silence(duration: Double = 1.0) -> [Int16] {
        [Int16](repeating: 0, count: Int(duration * Double(sampleRate)))
    }

    /// Wraps mono 16-bit PCM samples in a minimal WAV container.
    static func makeWAV(samples: [Int16]) -> Data {
        let numChannels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data()

        func append(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }
        func append(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func append(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append(UInt32(36 + dataSize))
        append("WAVE")

        append("fmt ")
        append(UInt32(16))                 // PCM subchunk size
        append(UInt16(1))                  // PCM format
        append(UInt16(numChannels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(blockAlign))
        append(UInt16(bitsPerSample))

        append("data")
        append(UInt32(dataSize))
        for sample in samples {
            var v = sample.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        return data
    }
}
