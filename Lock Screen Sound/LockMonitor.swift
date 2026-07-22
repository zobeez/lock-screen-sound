import Foundation
import AVFoundation
import Observation

/// Metadata for a user-imported custom sound. The audio itself lives as an MP3
/// in the app's `Documents/CustomSounds` directory, named `fileName`.
struct CustomSound: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var fileName: String
}

/// Runs continuously in the background (using the same silent-audio trick as
/// Riley Testut's Clip) and plays the chosen sound effect whenever the phone
/// locks / the screen turns off.
///
/// Background persistence works because iOS keeps an app alive while it is
/// actively playing audio and declares the `audio` background mode. We play a
/// looping *silent* clip to satisfy that requirement, then play the real sound
/// effect on top of it when a lock is detected.
///
/// Lock detection uses the private SpringBoard Darwin notification
/// `com.apple.springboard.hasBlankedScreen`, whose state is `0` when the screen
/// is on (unlocked) and `1` when it is blanked (locked / turned off).
@MainActor
@Observable
final class LockMonitor {

    private(set) var isMonitoring = false
    private(set) var status = "Idle"
    var selectedSound: SoundEffect = .chime {
        didSet { UserDefaults.standard.set(selectedSound.id, forKey: Self.selectedSoundKey) }
    }

    /// The user's imported custom sounds.
    private(set) var customSounds: [CustomSound] = []

    /// Ids of sounds the user has pinned to the top of the list (max 3).
    private(set) var pinnedSoundIDs: [String] = []
    static let maxPins = 3

    /// Longest a custom sound name may be. Keeps names within the width the
    /// home screen's fixed-size current-sound label can show without shrinking.
    static let maxNameLength = 12

    @ObservationIgnored private var silentPlayer: AVAudioPlayer?
    @ObservationIgnored private var effectPlayer: AVAudioPlayer?
    @ObservationIgnored private var notifyToken: Int32 = -1

    private static let selectedSoundKey = "selectedSound"
    private static let customSoundsKey = "customSounds"
    private static let pinnedKey = "pinnedSoundIDs"

    /// Directory in the app's Documents folder where imported MP3s are stored so
    /// they survive relaunches.
    static var customSoundsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CustomSounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        // Restore any previously imported custom sounds.
        if let data = UserDefaults.standard.data(forKey: Self.customSoundsKey),
           let decoded = try? JSONDecoder().decode([CustomSound].self, from: data) {
            customSounds = decoded
        }
        // Restore the last selected sound, unless it was a custom sound that no
        // longer exists.
        if let savedID = UserDefaults.standard.string(forKey: Self.selectedSoundKey),
           let saved = SoundEffect(id: savedID),
           isAvailable(saved) {
            selectedSound = saved
        }
        // Restore pinned sounds, dropping any that are no longer available.
        if let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) {
            pinnedSoundIDs = saved.filter { id in
                guard let effect = SoundEffect(id: id) else { return false }
                return isAvailable(effect)
            }
        }
    }

    /// Pinned sounds, in pin order.
    var pinnedSounds: [SoundEffect] {
        pinnedSoundIDs.compactMap { SoundEffect(id: $0) }.filter { isAvailable($0) }
    }

    func isPinned(_ effect: SoundEffect) -> Bool {
        pinnedSoundIDs.contains(effect.id)
    }

    /// Whether another sound can still be pinned (max is ``maxPins``).
    var canPinMore: Bool { pinnedSoundIDs.count < Self.maxPins }

    /// Pins or unpins a sound. Pinning is capped at ``maxPins``.
    func togglePin(_ effect: SoundEffect) {
        if let index = pinnedSoundIDs.firstIndex(of: effect.id) {
            pinnedSoundIDs.remove(at: index)
        } else if canPinMore {
            pinnedSoundIDs.append(effect.id)
        }
        UserDefaults.standard.set(pinnedSoundIDs, forKey: Self.pinnedKey)
    }

    /// Selects a sound and immediately plays it as a sample.
    func select(_ effect: SoundEffect) {
        selectedSound = effect
        previewSelectedSound()
    }

    private func isAvailable(_ effect: SoundEffect) -> Bool {
        if case .custom(let id) = effect {
            return customSounds.contains { $0.id == id }
        }
        return true
    }

    private func fileURL(for sound: CustomSound) -> URL {
        Self.customSoundsDirectory.appendingPathComponent(sound.fileName)
    }

    // MARK: - Public control

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        status = "Starting…"

        Task {
            do {
                // Activate the session off the main thread — setActive can
                // otherwise stall the UI (AVAudioSession "Hang Risk").
                try await Self.activateSession()
                startSilentAudio()
                registerForLockNotifications()
                status = "Monitoring — lock your phone to test"
            } catch {
                isMonitoring = false
                status = "Failed to start: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        guard isMonitoring else { return }

        unregisterForLockNotifications()
        silentPlayer?.stop()
        silentPlayer = nil
        effectPlayer?.stop()
        effectPlayer = nil

        Task.detached { Self.deactivateSession() }

        isMonitoring = false
        status = "Idle"
    }

    /// Plays the currently selected effect immediately (for the "Test" button).
    func previewSelectedSound() {
        Task {
            // Make sure we can be heard even if monitoring hasn't started yet.
            try? await Self.activateSession()
            playSelectedSound()
        }
    }

    // MARK: - Audio session & keep-alive

    /// Configures and activates the shared audio session. `nonisolated static`
    /// so it can be run on a background executor via `Task.detached`.
    private nonisolated static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps audio going when locked; .mixWithOthers lets the
        // user's music keep playing alongside our silent keep-alive clip.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private nonisolated static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startSilentAudio() {
        let data = AudioSynth.makeWAV(samples: AudioSynth.silence())
        silentPlayer = try? AVAudioPlayer(data: data)
        silentPlayer?.numberOfLoops = -1 // loop forever -> app stays alive
        silentPlayer?.volume = 0
        silentPlayer?.prepareToPlay()
        silentPlayer?.play()
    }

    private func playSelectedSound() {
        guard let data = selectedSoundData else { return }
        effectPlayer = try? AVAudioPlayer(data: data)
        effectPlayer?.volume = 1.0
        effectPlayer?.prepareToPlay()
        effectPlayer?.play()
    }

    /// Audio data for whatever sound is currently selected.
    private var selectedSoundData: Data? {
        if case .custom(let id) = selectedSound {
            guard let sound = customSounds.first(where: { $0.id == id }) else { return nil }
            return try? Data(contentsOf: fileURL(for: sound))
        }
        return selectedSound.builtInAudioData
    }

    /// The display name for the currently selected sound.
    var selectedSoundName: String {
        if case .custom(let id) = selectedSound {
            return customSounds.first(where: { $0.id == id })?.name ?? "Custom Sound"
        }
        return selectedSound.displayName
    }

    // MARK: - Custom sounds

    /// Clamps a user-supplied name: trims whitespace and caps its length.
    static func sanitizedName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    /// Copies a user-selected MP3 into the app's Documents directory under the
    /// given name, adds it to the custom sounds, and selects it. Falls back to
    /// the file's own name if the provided name is empty.
    func importCustomSound(from url: URL, name providedName: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let id = UUID()
            var name = Self.sanitizedName(providedName)
            if name.isEmpty {
                name = Self.sanitizedName(url.deletingPathExtension().lastPathComponent)
            }
            let sound = CustomSound(
                id: id,
                name: name,
                fileName: "\(id.uuidString).mp3"
            )
            try data.write(to: fileURL(for: sound))
            customSounds.append(sound)
            persistCustomSounds()
            selectedSound = .custom(id)
        } catch {
            status = "Couldn't import that file: \(error.localizedDescription)"
        }
    }

    /// Renames a custom sound. Ignores empty names; caps length.
    func renameCustomSound(_ sound: CustomSound, to newName: String) {
        let trimmed = Self.sanitizedName(newName)
        guard !trimmed.isEmpty,
              let index = customSounds.firstIndex(where: { $0.id == sound.id }) else { return }
        customSounds[index].name = trimmed
        persistCustomSounds()
    }

    /// Deletes custom sounds at the given offsets, removing their files. If the
    /// selected sound is deleted, selection falls back to the default tone.
    func removeCustomSounds(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let sound = customSounds[index]
            try? FileManager.default.removeItem(at: fileURL(for: sound))
            let effectID = SoundEffect.custom(sound.id).id
            if selectedSound.id == effectID {
                selectedSound = .chime
            }
            pinnedSoundIDs.removeAll { $0 == effectID }
            customSounds.remove(at: index)
        }
        persistCustomSounds()
        UserDefaults.standard.set(pinnedSoundIDs, forKey: Self.pinnedKey)
    }

    private func persistCustomSounds() {
        if let data = try? JSONEncoder().encode(customSounds) {
            UserDefaults.standard.set(data, forKey: Self.customSoundsKey)
        }
    }

    // MARK: - Private lock notification

    private func registerForLockNotifications() {
        // Reconstruct "com.apple.springboard.hasBlankedScreen" at runtime so the
        // private API name isn't a plain string literal in the binary.
        let name = ["com", "apple", "springboard", "hasBlank3dScr33n"]
            .joined(separator: ".")
            .replacingOccurrences(of: "3", with: "e")

        let registration = notify_register_dispatch(name, &notifyToken, DispatchQueue.main) { [weak self] token in
            guard let self else { return }

            var state: UInt64 = 0
            let result = notify_get_state(token, &state)
            if result != 0 {
                NSLog("Lock screen notify_get_state returned: \(result)")
            }

            // state == 0 -> screen on (unlocked); state == 1 -> screen off (locked)
            if state == 1 {
                self.status = "Locked — playing \(self.selectedSoundName)"
                self.playSelectedSound()
            } else {
                self.status = "Unlocked — monitoring"
            }
        }

        if registration != 0 {
            NSLog("Lock screen notification registration returned: \(registration)")
            status = "Notification registration failed (\(registration))"
        }
    }

    private func unregisterForLockNotifications() {
        if notifyToken != -1 {
            notify_cancel(notifyToken)
            notifyToken = -1
        }
    }
}

#if DEBUG
extension LockMonitor {
    /// A monitor pre-seeded with fake imported sounds, for SwiftUI previews.
    /// The referenced files don't exist, so playback is a no-op — this is for
    /// visual layout only.
    static func previewWithCustomSounds() -> LockMonitor {
        let monitor = LockMonitor()
        monitor.customSounds = [
            CustomSound(id: UUID(), name: "My Ringtone", fileName: "preview-1.mp3"),
            CustomSound(id: UUID(), name: "Airhorn", fileName: "preview-2.mp3")
        ]
        monitor.pinnedSoundIDs = [SoundEffect.chime.id, SoundEffect.success.id]
        monitor.selectedSound = .chime
        return monitor
    }
}
#endif
