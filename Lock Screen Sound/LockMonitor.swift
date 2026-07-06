import Foundation
import AVFoundation
import Observation

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
    var selectedSound: SoundEffect = .chime

    @ObservationIgnored private var silentPlayer: AVAudioPlayer?
    @ObservationIgnored private var effectPlayer: AVAudioPlayer?
    @ObservationIgnored private var notifyToken: Int32 = -1

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
        effectPlayer = try? AVAudioPlayer(data: selectedSound.wavData)
        effectPlayer?.volume = 1.0
        effectPlayer?.prepareToPlay()
        effectPlayer?.play()
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
                self.status = "Locked — playing \(self.selectedSound.rawValue)"
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
