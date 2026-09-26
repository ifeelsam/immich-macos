import SwiftUI

struct WelcomeView: View {
    let session: ImmichSession

    var body: some View {
        HStack(spacing: 0) {
            // Hero panel
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Image(systemName: "camera.aperture")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Immich Photos")
                        .font(.largeTitle.weight(.bold))
                    Text("A native macOS library for your self-hosted Immich server. Fast, private, and shaped around Apple Photos.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    FeatureRow(icon: "photo.on.rectangle", text: "Paged photo grid with month sections")
                    FeatureRow(icon: "person.2", text: "People and Places discovery")
                    FeatureRow(icon: "square.and.arrow.down", text: "Direct import and full-resolution download")
                    FeatureRow(icon: "lock", text: "API keys stay in macOS Keychain")
                }
                .font(.callout)
                Spacer()
                Text("Requires Immich v1.135+ · macOS 14+")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Connect panel
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect to Immich")
                        .font(.title2.weight(.semibold))
                    Text("Paste your server URL and an API key with asset and album read access.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ConnectionForm(session: session, compact: false)
                Spacer()
            }
            .padding(44)
            .frame(width: 460)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.blue)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    let session: ImmichSession
    let onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Immich Server")
                    .font(.title2.weight(.semibold))
                Text("Connection details and key storage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ConnectionForm(session: session, compact: true) {
                onConnected()
                dismiss()
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("Stored only in macOS Keychain", systemImage: "key.fill")
                    .font(.callout)
                Text("Grant asset.read, asset.view, asset.download, album.read, album.create, asset.update and asset.delete according to the features you want to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .connected = session.status {
                HStack {
                    Spacer()
                    Button("Sign Out", role: .destructive) {
                        session.signOut()
                        dismiss()
                    }
                }
            }
        }
        .padding(26)
        .frame(width: 520)
    }
}

private struct ConnectionForm: View {
    let session: ImmichSession
    let compact: Bool
    var onConnected: () -> Void = {}
    @State private var serverURL = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("https://immich.example.com", text: $serverURL, prompt: Text("https://immich.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .accessibilityLabel("Immich server URL")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                SecureField("Paste an Immich API key", text: $apiKey, prompt: Text("Paste an Immich API key"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Immich API key")
            }
            HStack(spacing: 10) {
                Button("Connect") {
                    Task {
                        if await session.connect(serverURL: serverURL, apiKey: apiKey) {
                            onConnected()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.isEmpty || isConnecting)
                .keyboardShortcut(.defaultAction)
                if isConnecting { ProgressView().controlSize(.small) }
                Spacer()
            }
            .padding(.top, 2)
            if case .failed(let message) = session.status {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .connected = session.status, compact {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("New Album").font(.title2.weight(.semibold))
                Text("Give your album a name. Selected photos will be added automatically.")
                    .font(.callout).foregroundStyle(.secondary)
            }
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
        .frame(width: 380)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismiss()
        onCreate(trimmed)
    }
}
