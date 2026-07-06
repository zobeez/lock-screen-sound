import SwiftUI
import UniformTypeIdentifiers

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension Color {
    /// The app's gold accent, matching the app icon.
    static let brandGold = Color(red: 0.91, green: 0.70, blue: 0.23)
}

struct ContentView: View {
    @State private var monitor = LockMonitor()
    @State private var showImporter = false
    @State private var showManage = false
    @State private var ringPulse = false
    @State private var testBounce = 0

    init(monitor: LockMonitor? = nil) {
        _monitor = State(initialValue: monitor ?? LockMonitor())
    }

    /// Built-in sounds plus any imported custom sounds.
    private var availableSounds: [SoundEffect] {
        SoundEffect.builtInCases + monitor.customSounds.map { SoundEffect.custom($0.id) }
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            soundsCard
            Spacer(minLength: 8)
            monitorCard
            footerNote
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                monitor.importCustomSound(from: url)
            }
        }
        .sheet(isPresented: $showManage) {
            ManageSoundsSheet(monitor: monitor)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.brandGold.opacity(0.16), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Color.brandGold.gradient)
                .symbolEffect(.variableColor.iterative, isActive: monitor.isMonitoring)
            Text("Lock Screen Sound")
                .font(.title.weight(.bold))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sounds

    private var soundsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SOUND")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !monitor.customSounds.isEmpty {
                    Button("Edit") { showManage = true }
                        .font(.caption.weight(.semibold))
                        .tint(.brandGold)
                }
            }

            Picker("Sound Effect", selection: $monitor.selectedSound) {
                ForEach(availableSounds) { effect in
                    Text(title(for: effect)).tag(effect)
                }
            }
            .pickerStyle(.menu)
            .font(.title3.weight(.semibold))
            .tint(.primary)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 14))

            HStack(spacing: 12) {
                Button {
                    monitor.previewSelectedSound()
                    testBounce += 1
                } label: {
                    Label("Test Sound", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .symbolEffect(.bounce, value: testBounce)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandGold)

                Button {
                    showImporter = true
                } label: {
                    Label("Import MP3", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private func title(for effect: SoundEffect) -> String {
        if case .custom(let id) = effect {
            return monitor.customSounds.first(where: { $0.id == id })?.name ?? "Custom Sound"
        }
        return effect.displayName
    }

    // MARK: - Monitoring

    private var monitorCard: some View {
        VStack(spacing: 16) {
            ZStack {
                if monitor.isMonitoring {
                    Circle()
                        .stroke(Color.green.opacity(0.5), lineWidth: 4)
                        .frame(width: 130, height: 130)
                        .scaleEffect(ringPulse ? 1.7 : 1.0)
                        .opacity(ringPulse ? 0 : 0.7)
                }

                Button {
                    withAnimation(.snappy) {
                        monitor.isMonitoring ? monitor.stop() : monitor.start()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(monitor.isMonitoring
                                  ? AnyShapeStyle(Color.red.gradient)
                                  : AnyShapeStyle(Color.green.gradient))
                            .frame(width: 130, height: 130)
                            .shadow(color: (monitor.isMonitoring ? Color.red : Color.green).opacity(0.4),
                                    radius: 18, y: 8)
                        Image(systemName: monitor.isMonitoring ? "stop.fill" : "play.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: monitor.isMonitoring)
                    }
                }
                .buttonStyle(PressableStyle())
            }
            .frame(height: 150)

            Text(monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                .font(.title2.weight(.bold))

            HStack(spacing: 8) {
                Circle()
                    .fill(monitor.isMonitoring ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(monitor.status)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .animation(.default, value: monitor.status)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 28))
        .onChange(of: monitor.isMonitoring) { _, active in
            if active {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    ringPulse = true
                }
            } else {
                ringPulse = false
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Keep this app open, then lock your phone to hear the selected sound. It uses continuous background audio and a private API, so it won't pass App Store review.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
}

/// A sheet for renaming and removing the user's imported sounds.
private struct ManageSoundsSheet: View {
    let monitor: LockMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: CustomSound?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(monitor.customSounds) { sound in
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(Color.brandGold)
                        Text(sound.name)
                        Spacer()
                        Button {
                            renaming = sound
                            newName = sound.name
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .tint(.brandGold)
                    }
                }
                .onDelete { monitor.removeCustomSounds(at: $0) }
            }
            .overlay {
                if monitor.customSounds.isEmpty {
                    ContentUnavailableView(
                        "No Imported Sounds",
                        systemImage: "waveform",
                        description: Text("Use Import MP3 to add your own sounds.")
                    )
                }
            }
            .navigationTitle("Your Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Sound", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let sound = renaming { monitor.renameCustomSound(sound, to: newName) }
                    renaming = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A button style that gives a subtle press-down scale.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview("Default") {
    ContentView()
}

#if DEBUG
#Preview("Imported MP3") {
    ContentView(monitor: .previewWithCustomSounds())
}

#Preview("Manage sounds") {
    ManageSoundsSheet(monitor: .previewWithCustomSounds())
}
#endif
