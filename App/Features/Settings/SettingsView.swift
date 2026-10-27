import BuzzCore
import SwiftUI

/// Display name (applies to the next game, saved with Save) and sound (applies immediately).
/// Presented as a sheet from Home.
struct SettingsView: View {
    @Environment(Profile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @AppStorage(SoundPlayer.enabledKey) private var soundEnabled = true
    @AppStorage(Diagnostics.enabledKey) private var debugLogEnabled = Diagnostics.defaultEnabled
    @State private var debugLogSize = 0
    #if DEBUG
    @AppStorage(TransportKind.key) private var transport = TransportKind.network.rawValue
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NameField(text: $draft)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Display name")
                } footer: {
                    Text("Shown to other players. Up to \(Profile.maxNameLength) characters.")
                }
                Section {
                    Toggle("Sound effects", isOn: $soundEnabled)
                } header: {
                    Text("Game")
                } footer: {
                    Text("The buzzer sound follows the silent switch. Haptics are always on.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
                Section {
                    Toggle("Record debug log", isOn: $debugLogEnabled)
                    if debugLogSize > 0 || debugLogEnabled {
                        LabeledContent("Log size", value: ByteCountFormatter.string(fromByteCount: Int64(debugLogSize), countStyle: .file))
                        ShareLink(item: DebugLogFile(label: "\(profile.name)-\(Diagnostics.deviceModel)"),
                                  preview: SharePreview("BuzzLight debug log")) {
                            Label("Share debug log", systemImage: "square.and.arrow.up")
                        }
                        .disabled(debugLogSize == 0)
                        Button("Clear debug log", role: .destructive) {
                            DebugLog.shared.clear()
                            debugLogSize = DebugLog.shared.sizeInBytes
                        }
                        .disabled(debugLogSize == 0)
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Records what the game does on this phone (connections, messages, timings) to a file that stays on the phone until you share it. Turn it on before reproducing a problem.")
                }
                #if DEBUG
                Section {
                    Picker("Transport", selection: $transport) {
                        ForEach(TransportKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("DEBUG builds only. Applies to the next game. Every phone in a game must use the same transport.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.setName(draft)
                        dismiss()
                    }
                    .disabled(Profile.normalized(draft) == nil)
                }
            }
            .onAppear {
                draft = profile.name
                debugLogSize = DebugLog.shared.sizeInBytes
            }
            .onChange(of: debugLogEnabled) { _, on in
                Diagnostics.setEnabled(on, profile: profile)
                debugLogSize = DebugLog.shared.sizeInBytes
            }
        }
    }
}

extension Bundle {
    /// "0.2.0 (1)"
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(Profile(defaults: UserDefaults(suiteName: "preview")!))
}
