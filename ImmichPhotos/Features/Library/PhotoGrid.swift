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
            LazyVStack(alignment: .leading, spacing: 32, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: gridSize), spacing: 12)],
                            spacing: 12
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
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.title)
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Text("\(section.assets.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
        .animation(.easeInOut(duration: 0.22), value: gridSize)
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
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            // Square layout cell. The photo fills and crops to the square;
            // everything lives in overlays so image sizes can't break layout.
            Color(nsColor: .quaternaryLabelColor).opacity(0.35)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .clipped()
                            .allowsHitTesting(false)
                    } else if failed {
                        VStack(spacing: 6) {
                            Image(systemName: "photo").font(.title2)
                            Text("Unavailable").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .overlay {
                    if isHovering && !selectionMode {
                        LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if asset.isVideo {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption2.weight(.bold))
                            Text("Video")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if asset.isFavorite == true {
                        Image(systemName: "heart.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if selectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? .blue : .black.opacity(0.3))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                }
                .opacity(isSelected && selectionMode ? 0.85 : 1)
                .brightness(isHovering && !selectionMode ? 0.04 : 0)
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.originalFileName)
        .onHover { isHovering = $0 }
        .task(id: asset.id) {
            guard image == nil else { return }
            do { image = try await thumbnails.image(for: asset.id, preview: false, client: client) }
            catch { failed = true }
        }
    }
}
