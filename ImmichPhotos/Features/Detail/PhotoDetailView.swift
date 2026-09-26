import SwiftUI
import AVKit
import AVFoundation
import AppKit

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
    @State private var showInfo = false
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
        HSplitView {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .frame(minWidth: 400)
            .safeAreaInset(edge: .bottom) {
                captionBar
            }

            if showInfo {
                inspector
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onClose) {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)
                .help("Back to library (Esc)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { toggleFavorite() } label: {
                    Label(
                        currentAsset.isFavorite == true ? "Unfavorite" : "Favorite",
                        systemImage: currentAsset.isFavorite == true ? "heart.fill" : "heart"
                    )
                }
                .tint(currentAsset.isFavorite == true ? .red : nil)
                .disabled(isMutating)
                .help("Favorite (F)")
                .keyboardShortcut("f", modifiers: [])

                Button { toggleArchived() } label: {
                    Label(
                        currentAsset.isArchived == true ? "Unarchive" : "Archive",
                        systemImage: currentAsset.isArchived == true ? "tray.and.arrow.up.fill" : "archivebox"
                    )
                }
                .disabled(isMutating)
                .help("Archive")

                Button(action: saveOriginal) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(isMutating)
                .help("Download original")

                Button {
                    withAnimation { showInfo.toggle() }
                } label: {
                    Label("Info", systemImage: showInfo ? "info.circle.fill" : "info.circle")
                }
                .help("Show info (I)")
                .keyboardShortcut("i", modifiers: [])

                Menu {
                    Button("Delete from Immich", role: .destructive) { onDelete(currentAsset.id) }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(isMutating)
            }
        }
        .focusable()
        .focused($hasFocus)
        .onExitCommand(perform: onClose)
        .onAppear { hasFocus = true }
        .task(id: currentAsset.id) { await load() }
        .alert("Couldn't complete that action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        if let player {
            NativePlayer(player: player)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(24)
                .draggable(image)
        } else if isLoading {
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text("Loading photo…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("Couldn't Load Photo", systemImage: "exclamationmark.triangle")
        }
    }

    private var captionBar: some View {
        VStack(spacing: 2) {
            Text(currentAsset.originalFileName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let date = currentAsset.createdDate {
                    Text(DateFormatter.detail.string(from: date))
                }
                if let place, currentAsset.createdDate != nil {
                    Text("·").foregroundStyle(.quaternary)
                    Text(place).lineLimit(1)
                } else if let place {
                    Text(place).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Info")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Filename", value: currentAsset.originalFileName)
                    if let date = currentAsset.createdDate {
                        InfoRow(label: "Taken", value: DateFormatter.detail.string(from: date))
                    }
                    if let place {
                        InfoRow(label: "Location", value: place)
                    }
                    InfoRow(label: "Type", value: currentAsset.isVideo ? "Video" : "Photo")
                    if let size = currentAsset.exifInfo?.fileSizeInByte {
                        InfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if let lat = currentAsset.exifInfo?.latitude,
                       let lon = currentAsset.exifInfo?.longitude {
                        InfoRow(label: "GPS", value: String(format: "%.4f, %.4f", lat, lon))
                    }
                    InfoRow(label: "Favorite", value: currentAsset.isFavorite == true ? "Yes" : "No")
                    InfoRow(label: "Archived", value: currentAsset.isArchived == true ? "Yes" : "No")
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Button { toggleFavorite() } label: {
                        Label(currentAsset.isFavorite == true ? "Unfavorite" : "Favorite", systemImage: "heart")
                    }
                    .buttonStyle(.link).disabled(isMutating)
                    Button { toggleArchived() } label: {
                        Label(currentAsset.isArchived == true ? "Unarchive" : "Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(.link).disabled(isMutating)
                    Button(action: saveOriginal) {
                        Label("Download Original", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.link).disabled(isMutating)
                }
                .font(.callout)
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var place: String? {
        [currentAsset.exifInfo?.city, currentAsset.exifInfo?.state, currentAsset.exifInfo?.country]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            .nilIfEmpty
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        player = nil
        image = nil
        if currentAsset.isVideo {
            let resource = client.videoPlaybackResource(id: currentAsset.id)
            let media = AVURLAsset(url: resource.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resource.headers])
            if (try? await media.load(.isPlayable)) == true {
                let player = AVPlayer(playerItem: AVPlayerItem(asset: media))
                self.player = player
                player.play()
            } else {
                errorMessage = "Immich couldn't stream this video."
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

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
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
