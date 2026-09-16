import SwiftUI

struct PhotoGrid: View {
    let sections: [LibraryViewModel.Section]
    let selectedIDs: Set<String>
    let selectionMode: Bool
    let gridSize: CGFloat
    let client: ImmichClient
    let thumbnails: ThumbnailStore
    let onOpen: (ImmichAsset) -> Void
    let onToggleSelection: (ImmichAsset) -> Void
    let onNearEnd: (ImmichAsset) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: gridSize), spacing: 3)],
                            spacing: 3
                        ) {
                            ForEach(section.assets) { asset in
                                AssetTile(
                                    asset: asset,
                                    isSelected: selectedIDs.contains(asset.id),
                                    selectionMode: selectionMode,
                                    client: client,
                                    thumbnails: thumbnails
                                ) {
                                    if selectionMode { onToggleSelection(asset) }
                                    else { onOpen(asset) }
                                }
                                .onAppear { onNearEnd(asset) }
                            }
                        }
                    } header: {
                        Text(section.title)
                            .font(.title3.weight(.bold))
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial)
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }
}

private struct AssetTile: View {
    let asset: ImmichAsset
    let isSelected: Bool
    let selectionMode: Bool
    let client: ImmichClient
    let thumbnails: ThumbnailStore
    let action: () -> Void
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if failed {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
                if asset.isVideo {
                    Label("Video", systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.52), in: Capsule())
                        .padding(6)
                }
                if asset.isFavorite == true {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.52), in: Circle())
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? .blue : .black.opacity(0.35))
                        .shadow(radius: 1)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(.blue, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.originalFileName)
        .task(id: asset.id) {
            guard image == nil else { return }
            do { image = try await thumbnails.image(for: asset.id, preview: false, client: client) }
            catch { failed = true }
        }
    }
}
