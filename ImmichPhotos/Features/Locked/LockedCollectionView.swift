import SwiftUI
import AppKit

/// Immich intentionally rejects API-key access to visibility=locked assets. The
/// server accepts a PIN only for a browser/session token; never collect that PIN
/// in this app while it is authenticated solely with a long-lived API key.
struct LockedCollectionView: View {
    let serverURL: String

    var body: some View {
        ContentUnavailableView {
            Label("Locked Photos Stay Locked", systemImage: "lock.fill")
        } description: {
            Text("Immich requires a signed-in session and your PIN to open this collection. API keys cannot receive that elevated access, so this app will not retry or ask you to paste a PIN here.")
        } actions: {
            Button("Open Immich to Unlock") {
                guard let url = URL(string: serverURL) else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Locked")
    }
}
