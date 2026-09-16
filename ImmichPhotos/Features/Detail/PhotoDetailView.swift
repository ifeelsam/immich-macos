import SwiftUI
import AVKit
import AVFoundation

struct PhotoDetailView: View {
    let asset: ImmichAsset
    let client: ImmichClient
    let thumbnails: ThumbnailStore
    let onClose: () -> Void
    let onUpdated: (ImmichAsset) -> Void
    let onDelete: (String) -> Void

    @State private var currentAsset: ImmichAsset
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMutating = false
    @FocusState private var hasFocus: Bool

    init(
        asset: ImmichAsset,
        client: ImmichClient,
        thumbnails: ThumbnailStore,
        onClose: @escaping () -> Void,
        onUpdated: @escaping (ImmichAsset) -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        self.asset = asset
        self.client = client
        self.thumbnails = thumbnails
        self.onClose = onClose
        self.onUpdated = onUpdated
        self.onDelete = onDelete
        _currentAsset = State(initialValue: asset)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(OverlayButtonStyle())
            .keyboardShortcut(.cancelAction)
            .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button { toggleFavorite() } label: {
                    Label(currentAsset.isFavorite == true ? "Unfavorite" : "Favorite", systemImage: currentAsset.isFavorite == true ? "heart.fill" : "heart")
                }
                Button { toggleArchived() } label: {
                    Label(currentAsset.isArchived == true ? "Unarchive" : "Archive", systemImage: currentAsset.isArchived == true ? "tray.and.arrow.up.fill" : "archivebox")
                }
                Button(action: saveOriginal) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                Menu {
                    Button("Delete from Immich", role: .destructive) { onDelete(currentAsset.id) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            .buttonStyle(OverlayButtonStyle())
            .disabled(isMutating)
            .padding(18)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                Text(currentAsset.originalFileName)
                    .font(.callout.weight(.medium))
                if let date = currentAsset.createdDate {
                    Text(DateFormatter.detail.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let place = place {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(20)
        }
        .focusable()
        .focused($hasFocus)
        .onExitCommand(perform: onClose)
        .onAppear { hasFocus = true }
        .task(id: currentAsset.id) { await load() }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        if let player {
            NativePlayer(player: player)
                .ignoresSafeArea()
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(38)
        } else if isLoading {
            ProgressView().tint(.white)
        } else {
            ContentUnavailableView("Couldn’t Load Photo", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.white)
        }
    }

    private var place: String? {
        [currentAsset.exifInfo?.city, currentAsset.exifInfo?.state, currentAsset.exifInfo?.country]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            .nilIfEmpty
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if currentAsset.isVideo {
            let resource = client.videoPlaybackResource(id: currentAsset.id)
            let media = AVURLAsset(url: resource.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resource.headers])
            if (try? await media.load(.isPlayable)) == true {
                let player = AVPlayer(playerItem: AVPlayerItem(asset: media))
                self.player = player
                player.play()
            } else {
                errorMessage = "Immich couldn’t stream this video."
            }
        } else {
            do { image = try await thumbnails.image(for: currentAsset.id, preview: true, client: client) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func toggleFavorite() {
        let newValue = !(currentAsset.isFavorite ?? false)
        mutate { try await client.updateAsset(id: currentAsset.id, isFavorite: newValue) } update: {
            currentAsset.isFavorite = newValue
            onUpdated(currentAsset)
        }
    }

    private func toggleArchived() {
        let newValue = !(currentAsset.isArchived ?? false)
        mutate { try await client.updateAsset(id: currentAsset.id, isArchived: newValue) } update: {
            currentAsset.isArchived = newValue
            onUpdated(currentAsset)
        }
    }

    private func mutate(_ operation: @escaping () async throws -> Void, update: @escaping () -> Void) {
        Task {
            isMutating = true
            defer { isMutating = false }
            do { try await operation(); update() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func saveOriginal() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = currentAsset.originalFileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do { try await client.downloadOriginal(id: currentAsset.id).write(to: destination, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .frame(width: 40, height: 40)
            .background(.black.opacity(configuration.isPressed ? 0.72 : 0.48), in: Circle())
            .foregroundStyle(.white)
            .contentShape(Circle())
    }
}

private struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
