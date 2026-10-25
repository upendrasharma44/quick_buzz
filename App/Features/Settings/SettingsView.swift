import SwiftUI

/// Display name (applies to the next game, saved with Save) and sound (applies immediately).
/// Presented as a sheet from Home.
struct SettingsView: View {
    @Environment(Profile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @AppStorage(SoundPlayer.enabledKey) private var soundEnabled = true

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
            .onAppear { draft = profile.name }
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
