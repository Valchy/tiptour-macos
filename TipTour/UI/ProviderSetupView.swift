import SwiftUI

struct ProviderSetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderKeyCard(
                title: "Gemini realtime",
                detail: "Speak with Ctrl+Option. Voice and optional screenshots go to Google.",
                keyName: "geminiAPIKey"
            )
            ProviderKeyCard(
                title: "JEV · TypeSafe",
                detail: "Type with Ctrl+K. JEV chooses clicks from locally detected screen labels. Text context goes to TypeSafe; images stay on your Mac.",
                keyName: "jevAPIKey"
            )
            Text("Keys are stored in macOS Keychain. Add a key only for the mode you use.")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }
}

private struct ProviderKeyCard: View {
    let title: String
    let detail: String
    let keyName: String
    @State private var input = ""
    @State private var hasSavedKey = false
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(hasSavedKey ? "Key saved" : "Key needed")
                    .font(.system(size: 11))
                    .foregroundColor(hasSavedKey ? DS.Colors.success : DS.Colors.textTertiary)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField(hasSavedKey ? "Paste a replacement key" : "Paste your API key", text: $input)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(title) API key")
                .onSubmit { save() }
            HStack {
                Button("Save key", action: save)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pointerCursor()
                Button("Remove key") {
                    if KeychainStore.delete(forKey: keyName) {
                        hasSavedKey = false
                        input = ""
                        status = "Removed"
                    } else {
                        status = "Could not remove the key. Try again."
                    }
                }
                .disabled(!hasSavedKey)
                .pointerCursor()
                Text(status).font(.system(size: 11)).foregroundColor(DS.Colors.textSecondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(DS.Colors.surface1))
        .onAppear { hasSavedKey = !(KeychainStore.get(forKey: keyName) ?? "").isEmpty }
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainStore.set(trimmed, forKey: keyName) {
            hasSavedKey = true
            input = ""
            status = "Saved"
        } else {
            status = "Could not save to Keychain. Try again."
        }
    }
}
