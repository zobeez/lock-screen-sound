import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var monitor = LockMonitor()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sound Effect", selection: $monitor.selectedSound) {
                        ForEach(SoundEffect.allCases) { effect in
                            Text(effect.rawValue).tag(effect)
                        }
                    }
                    Text(monitor.selectedSound.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        monitor.previewSelectedSound()
                    } label: {
                        Label("Test Sound", systemImage: "play.circle")
                    }
                } header: {
                    Text("Sound")
                }

                Section {
                    Button {
                        monitor.isMonitoring ? monitor.stop() : monitor.start()
                    } label: {
                        Label(
                            monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                            systemImage: monitor.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(monitor.isMonitoring ? .red : .accentColor)

                    HStack {
                        Circle()
                            .fill(monitor.isMonitoring ? .green : .gray)
                            .frame(width: 10, height: 10)
                        Text(monitor.status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text("Keep this app running, then lock your phone to hear the selected sound. Uses continuous background audio and a private API, so it will not pass App Store review.")
                }
            }
            .navigationTitle("Lock Sound")
        }
    }
}

#Preview {
    ContentView()
}
