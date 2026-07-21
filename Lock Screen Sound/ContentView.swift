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
    /// The app's green accent, used for the active/selected state.
    static let brandGreen = Color(red: 0.30, green: 0.69, blue: 0.31)
    /// Purple accent, used for the "More" entry.
    static let brandPurple = Color(red: 0.52, green: 0.35, blue: 0.85)
    /// Light yellow fill for the current-sound card.
    static let softYellow = Color(red: 1.0, green: 0.95, blue: 0.78)
    /// Dark amber text that reads on the yellow card.
    static let cardText = Color(red: 0.34, green: 0.25, blue: 0.03)
}

struct ContentView: View {
    @State private var monitor: LockMonitor
    @State private var testBounce = 0
    @Environment(\.openURL) private var openURL

    init(monitor: LockMonitor? = nil) {
        _monitor = State(initialValue: monitor ?? LockMonitor())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header

                        Spacer(minLength: 24)

                        VStack(spacing: 22) {
                    NavigationLink {
                        AllSoundsView(monitor: monitor)
                    } label: {
                        HStack(spacing: 10) {
                            // Invisible chevron balances the trailing one so the
                            // text stays centered.
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.semibold))
                                .opacity(0)
                            VStack(spacing: 4) {
                                Text("CURRENT SOUND")
                                    .font(.caption.weight(.semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Color.cardText.opacity(0.55))
                                Text(monitor.selectedSoundName)
                                    .font(.system(size: 58, weight: .heavy))
                                    .foregroundStyle(.black)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .contentTransition(.numericText())
                            }
                            .frame(maxWidth: .infinity)
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.cardText.opacity(0.55))
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        // Liquid Glass, but pinned to the light appearance so it
                        // keeps the same cream look in dark mode (it sits on the
                        // fixed light-yellow card).
                        .glassEffect(in: .rect(cornerRadius: 24))
                        .environment(\.colorScheme, .light)
                    }
                    .buttonStyle(.plain)

                    Button {
                        monitor.previewSelectedSound()
                        testBounce += 1
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.brandGreen.gradient)
                                .frame(width: 104, height: 104)
                                .shadow(color: Color.brandGreen.opacity(0.4), radius: 14, y: 6)
                            Image(systemName: "play.fill")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(.white)
                                .symbolEffect(.bounce, value: testBounce)
                        }
                    }
                    .buttonStyle(PressableStyle())

                    Text("Test Sound")
                        .font(.headline)
                        .foregroundStyle(Color.cardText)

                    Divider()
                        .overlay(Color.cardText.opacity(0.25))
                        .padding(.horizontal, 8)

                    Text("Keep the app running in the background and this sound will play each time you lock your phone.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.cardText.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.softYellow, Color(red: 1.0, green: 0.84, blue: 0.48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 28)
                )
                .shadow(color: .black.opacity(0.10), radius: 14, y: 5)

                        aodWarning
                            .padding(.top, 16)

                        Spacer(minLength: 24)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .background(BrandBackground())
            }
            .toolbar(.hidden, for: .navigationBar)
            .tint(.brandGreen)
        }
        .task {
            // Monitoring is always on while the app is open.
            monitor.start()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.brandGold.gradient)
                .symbolEffect(.variableColor.iterative, isActive: monitor.isMonitoring)
            Text("Lock Screen Sound")
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// Warns that Always-On Display interferes with lock detection and offers a
    /// shortcut into Settings so the user can turn it off.
    private var aodWarning: some View {
        VStack(spacing: 8) {
            Label("Turn off Always-On Display", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brandGold)

            Text("Lock sounds won't work correctly while Always-On Display is on. Turn it off in Settings › Display & Brightness.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                // Deep-link to Settings › Display & Brightness (where the AOD
                // toggle lives). openSettingsURLString only opens this app's own
                // page, which doesn't contain the setting.
                if let url = URL(string: "App-Prefs:root=DISPLAY") {
                    openURL(url)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(.brandGreen)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.brandGold.opacity(0.12), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.brandGold.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 8)
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

/// A soft gold-tinted gradient behind the list, echoing the former UI.
private struct BrandBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.brandGold.opacity(0.18), Color(.systemGroupedBackground)],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

/// The full catalog: every sound (pinned first) plus importing.
private struct AllSoundsView: View {
    let monitor: LockMonitor
    @State private var showImporter = false
    @State private var renaming: CustomSound?
    @State private var newName = ""
    @State private var showPinLimit = false

    private var allSounds: [SoundEffect] {
        let pinned = monitor.pinnedSounds
        let defaults = SoundEffect.builtInCases.filter { !monitor.isPinned($0) }
        let custom = monitor.customSounds
            .map { SoundEffect.custom($0.id) }
            .filter { !monitor.isPinned($0) }
        return pinned + defaults + custom
    }

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import MP3", systemImage: "square.and.arrow.down")
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            } footer: {
                Text("Import your own MP3s, then swipe them to rename or delete.")
            }

            Section {
                ForEach(allSounds) { effect in
                    SoundRow(monitor: monitor, effect: effect, onPinLimitReached: { showPinLimit = true })
                        .swipeActions(edge: .trailing) {
                            if case .custom = effect {
                                Button(role: .destructive) {
                                    deleteCustom(effect)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    startRename(effect)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.brandGold)
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BrandBackground())
        .navigationTitle("All Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.brandGreen)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                monitor.importCustomSound(from: url)
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
        .alert("Pin Limit Reached", isPresented: $showPinLimit) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can pin up to \(LockMonitor.maxPins) sounds. Unpin one to make room for another.")
        }
    }

    private func startRename(_ effect: SoundEffect) {
        guard case .custom(let id) = effect,
              let sound = monitor.customSounds.first(where: { $0.id == id }) else { return }
        newName = sound.name
        renaming = sound
    }

    private func deleteCustom(_ effect: SoundEffect) {
        guard case .custom(let id) = effect,
              let index = monitor.customSounds.firstIndex(where: { $0.id == id }) else { return }
        monitor.removeCustomSounds(at: IndexSet(integer: index))
    }
}

/// A single tappable sound row: selecting it plays a sample; swipe to pin.
/// A fixed-width pin slot sits next to the title (occupied only when pinned) so
/// every row aligns consistently.
private struct SoundRow: View {
    let monitor: LockMonitor
    let effect: SoundEffect
    var onPinLimitReached: () -> Void = {}

    private var isSelected: Bool { monitor.selectedSound == effect }
    private var isPinned: Bool { monitor.isPinned(effect) }

    private var title: String {
        if case .custom(let id) = effect {
            return monitor.customSounds.first(where: { $0.id == id })?.name ?? "Custom Sound"
        }
        return effect.displayName
    }

    var body: some View {
        Button {
            monitor.select(effect)
        } label: {
            HStack(spacing: 10) {
                // Reserved leading pin slot — visible only when pinned — so all
                // titles are indented consistently.
                Image(systemName: "pin.fill")
                    .font(.body)
                    .foregroundStyle(Color.brandGold)
                    .rotationEffect(.degrees(-45))
                    .opacity(isPinned ? 1 : 0)
                    .frame(width: 20)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandGreen)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected
                           ? Color.brandGreen.opacity(0.14)
                           : Color(.secondarySystemGroupedBackground))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                if !isPinned && !monitor.canPinMore {
                    onPinLimitReached()
                } else {
                    // Move straight to/from the top with no fade animation.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { monitor.togglePin(effect) }
                }
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .tint(isPinned ? .gray : .brandGold)
        }
    }
}

#Preview("Home") {
    ContentView()
}

#if DEBUG
#Preview("Home + pinned & custom") {
    ContentView(monitor: .previewWithCustomSounds())
}

#Preview("All Sounds") {
    NavigationStack {
        AllSoundsView(monitor: .previewWithCustomSounds())
    }
}
#endif
