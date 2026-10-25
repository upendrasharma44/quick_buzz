import SwiftUI

/// First-launch screen: collects the display name other players will see.
struct NameEntryView: View {
    @Environment(Profile.self) private var profile
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { Profile.normalized(draft) != nil }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.tint)
            Text("Welcome to BuzzLight")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("What should other players call you?")
                .foregroundStyle(.secondary)
            NameField(text: $draft)
                .focused($focused)
                .onSubmit(save)
            Spacer()
            Button(action: save) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid)
        }
        .padding(24)
        .onAppear { focused = true }
    }

    private func save() {
        guard isValid else { return }
        profile.setName(draft)
    }
}

/// Large centred text field with the app's name rules (length cap, word capitalisation).
struct NameField: View {
    @Binding var text: String

    var body: some View {
        TextField("Your name", text: $text)
            .font(.title3)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .textContentType(.nickname)
            .submitLabel(.done)
            .padding(.vertical, 14)
            .padding(.horizontal)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: text) { _, new in
                if new.count > Profile.maxNameLength { text = String(new.prefix(Profile.maxNameLength)) }
            }
    }
}

#Preview {
    NameEntryView()
        .environment(Profile(defaults: UserDefaults(suiteName: "preview")!))
}
