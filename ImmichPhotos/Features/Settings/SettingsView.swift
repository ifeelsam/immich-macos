import SwiftUI

struct WelcomeView: View {
    let session: ImmichSession

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("Immich Photos")
                    .font(.largeTitle.weight(.bold))
                Text("A native macOS photo library for your Immich server.")
                    .foregroundStyle(.secondary)
            }
            ConnectionForm(session: session, compact: false)
                .frame(width: 440)
        }
        .padding(40)
    }
}

struct SettingsView: View {
    let session: ImmichSession
    let onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Immich Server")
                .font(.title2.weight(.semibold))
            ConnectionForm(session: session, compact: true) {
                onConnected()
                dismiss()
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Your API key is stored only in macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Grant asset.read, asset.view, asset.download, album.read, album.create, asset.update and asset.delete according to the features you want to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .connected = session.status {
                Button("Sign Out", role: .destructive) {
                    session.signOut()
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 510)
    }
}

private struct ConnectionForm: View {
    let session: ImmichSession
    let compact: Bool
    var onConnected: () -> Void = {}
    @State private var serverURL = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Server URL", text: $serverURL, prompt: Text("https://immich.example.com"))
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                .accessibilityLabel("Immich server URL")
            SecureField("API Key", text: $apiKey, prompt: Text("Paste an Immich API key"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Immich API key")
            HStack {
                Button("Connect") {
                    Task {
                        if await session.connect(serverURL: serverURL, apiKey: apiKey) {
                            onConnected()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.isEmpty || isConnecting)
                if isConnecting { ProgressView().controlSize(.small) }
                Spacer()
            }
            if case .failed(let message) = session.status {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            serverURL = session.serverURL
            apiKey = session.apiKey
        }
    }

    private var isConnecting: Bool {
        if case .connecting = session.status { return true }
        return false
    }
}

struct NewAlbumSheet: View {
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Album").font(.title2.weight(.semibold))
            TextField("Album name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismiss()
        onCreate(trimmed)
    }
}
