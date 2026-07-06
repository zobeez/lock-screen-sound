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
}

struct ContentView: View {
    @State private var monitor: LockMonitor
    @State private var showImporter = false

    init(monitor: LockMonitor? = nil) {
        _monitor = State(initialValue: monitor ?? LockMonitor())
    }

    /// The home list: pinned first, then default sounds, sized to fill the
    /// available height so "More" and the footer stay visible without scrolling.
    private func homeSounds(fitting height: CGFloat) -> [SoundEffect] {
        let rowHeight: CGFloat = 48
        // Space taken by the header, footer, "More" + "Import MP3" rows, insets.
        let reserved: CGFloat = 348
        let capacity = max(3, Int((height - reserved) / rowHeight))
        let pinned = monitor.pinnedSounds
        let unpinned = SoundEffect.builtInCases.filter { !monitor.isPinned($0) }
        let remaining = max(0, capacity - pinned.count)
        return pinned + Array(unpinned.prefix(remaining))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let sounds = homeSounds(fitting: geo.size.height)
                VStack(spacing: 0) {
                    header
                    List {
                        Section {
                            ForEach(sounds) { effect in
                                SoundRow(monitor: monitor, effect: effect)
                            }
                            NavigationLink {
                                AllSoundsView(monitor: monitor)
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                                    .foregroundStyle(Color.brandPurple)
                                    .fontWeight(.semibold)
                            }
                            .listRowBackground(Color(.secondarySystemGroupedBackground))

                            Button {
                                showImporter = true
                            } label: {
                                Label("Import MP3", systemImage: "square.and.arrow.down")
                            }
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    // Size the list to its content so the footer can center in
                    // whatever space is left below it. (+2 for the More and
                    // Import rows; the constant covers the group insets.)
                    .frame(height: CGFloat(sounds.count + 2) * 55 + 44)

                    footerNote
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(BrandBackground())
            .toolbar(.hidden, for: .navigationBar)
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
        .padding(.bottom, 8)
    }

    private var footerNote: some View {
        Text("Tap a sound to hear it and set it. Swipe a sound to pin up to \(LockMonitor.maxPins) to the top. Your chosen sound plays automatically when you lock your phone while the app is open.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
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
                ForEach(allSounds) { effect in
                    SoundRow(monitor: monitor, effect: effect)
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
                // Move straight to/from the top with no fade animation.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { monitor.togglePin(effect) }
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
