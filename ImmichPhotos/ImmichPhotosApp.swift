import SwiftUI
import UniformTypeIdentifiers

@main
struct ImmichPhotosApp: App {
    @State private var session = ImmichSession()
    @State private var library = LibraryViewModel()
    @State private var thumbnails = ThumbnailStore()
    @State private var route: LibraryRoute? = .library
    @State private var albums: [ImmichAlbum] = []
    @State private var selectedAsset: ImmichAsset?
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var showNewAlbum = false
    @State private var pendingDelete = Set<String>()
    @State private var errorMessage: String?
    @State private var isUploading = false
    @State private var gridSize: CGFloat = 150

    var body: some Scene {
        WindowGroup {
            Group {
                if let client = session.client, case .connected = session.status {
                    gallery(client: client)
                } else {
                    WelcomeView(session: session)
                }
            }
            .frame(minWidth: 920, minHeight: 620)
            .sheet(isPresented: $showSettings) {
                SettingsView(session: session) {
                    Task { await reloadConnection() }
                }
            }
            .sheet(isPresented: $showNewAlbum) {
                NewAlbumSheet { name in
                    Task { await createAlbum(named: name) }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: true
            ) { result in
                guard case let .success(urls) = result else { return }
                Task { await upload(urls) }
            }
            .confirmationDialog(
                "Delete \(pendingDelete.count == 1 ? "this photo" : "\(pendingDelete.count) items")?",
                isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
                titleVisibility: .visible
            ) {
                Button("Delete from Immich", role: .destructive) {
                    let ids = pendingDelete
                    pendingDelete = []
                    Task { await delete(ids: ids) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = [] }
            } message: {
                Text("Items move to the Immich trash according to your server’s retention settings.")
            }
            .alert("Immich Photos", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .commands {
            CommandGroup(after: .importExport) {
                Button("Import Photos…") { showImporter = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Refresh Library") {
                    guard let client = session.client else { return }
                    Task { await library.refresh(using: client) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }

    @ViewBuilder private func gallery(client: ImmichClient) -> some View {
        NavigationSplitView {
            Sidebar(route: $route, albums: albums)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            if let asset = selectedAsset {
                PhotoDetailView(
                    asset: asset,
                    client: client,
                    thumbnails: thumbnails,
                    onClose: { selectedAsset = nil },
                    onUpdated: { updated in library.replace(updated) },
                    onDelete: { id in
                        selectedAsset = nil
                        pendingDelete = [id]
                    }
                )
            } else if case .some(.people) = route {
                PeopleBrowser(client: client) { person in route = .person(person) }
            } else if case .some(.places) = route {
                PlacesBrowser(client: client) { selectedAsset = $0 }
            } else if case .some(.locked) = route {
                LockedCollectionView(serverURL: session.serverURL)
            } else {
                LibraryScreen(
                    model: library,
                    client: client,
                    thumbnails: thumbnails,
                    gridSize: $gridSize,
                    albums: albums,
                    isUploading: isUploading,
                    onOpen: { selectedAsset = $0 },
                    onSettings: { showSettings = true },
                    onImport: { showImporter = true },
                    onCreateAlbum: { showNewAlbum = true },
                    onAddToAlbum: { album in Task { await addSelection(to: album) } },
                    onDelete: { pendingDelete = Set(library.selectedAssets.map(\.id)) }
                )
            }
        }
        .task { await reloadConnection() }
        .onChange(of: route) { _, route in
            selectedAsset = nil
            guard let route, route != .people, route != .places, route != .locked,
                  let client = session.client else { return }
            Task { await library.load(route: route, using: client) }
        }
    }

    @MainActor private func reloadConnection() async {
        guard let client = session.client else { return }
        do {
            albums = try await client.albums()
            if let route, route != .people, route != .places, route != .locked {
                await library.load(route: route, using: client)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func upload(_ urls: [URL]) async {
        guard let client = session.client else { return }
        isUploading = true
        defer { isUploading = false }
        var failures = 0
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do { try await client.upload(fileURL: url) }
            catch { failures += 1 }
        }
        await library.refresh(using: client)
        if failures > 0 { errorMessage = "\(failures) item(s) could not be uploaded." }
    }

    @MainActor private func delete(ids: Set<String>) async {
        guard let client = session.client else { return }
        do {
            try await client.deleteAssets(ids: Array(ids))
            library.remove(ids: ids)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func createAlbum(named name: String) async {
        guard let client = session.client else { return }
        do {
            let album = try await client.createAlbum(name: name, assetIDs: library.selectedAssets.map(\.id))
            albums.append(album)
            albums.sort { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }
            library.clearSelection()
            route = .album(album)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func addSelection(to album: ImmichAlbum) async {
        guard let client = session.client else { return }
        do {
            try await client.addToAlbum(id: album.id, assetIDs: library.selectedAssets.map(\.id))
            library.clearSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct Sidebar: View {
    @Binding var route: LibraryRoute?
    let albums: [ImmichAlbum]

    var body: some View {
        List(selection: $route) {
            Section("Library") {
                Label("Library", systemImage: "photo.on.rectangle.angled")
                    .tag(LibraryRoute.library)
                Label("Favorites", systemImage: "heart")
                    .tag(LibraryRoute.favorites)
                Label("Videos", systemImage: "play.rectangle")
                    .tag(LibraryRoute.videos)
                Label("Archived", systemImage: "archivebox")
                    .tag(LibraryRoute.archived)
                Label("Locked", systemImage: "lock")
                    .tag(LibraryRoute.locked)
            }
            Section("Discover") {
                Label("People", systemImage: "person.2")
                    .tag(LibraryRoute.people)
                Label("Places", systemImage: "map")
                    .tag(LibraryRoute.places)
            }
            Section("Albums") {
                ForEach(albums) { album in
                    Label(album.albumName, systemImage: "rectangle.stack")
                        .tag(LibraryRoute.album(album))
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct LibraryScreen: View {
    @Bindable var model: LibraryViewModel
    let client: ImmichClient
    let thumbnails: ThumbnailStore
    @Binding var gridSize: CGFloat
    let albums: [ImmichAlbum]
    let isUploading: Bool
    let onOpen: (ImmichAsset) -> Void
    let onSettings: () -> Void
    let onImport: () -> Void
    let onCreateAlbum: () -> Void
    let onAddToAlbum: (ImmichAlbum) -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("Loading \(model.route.title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView(
                    "No Items",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Import photos or choose another library view.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Load Photos", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh(using: client) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                PhotoGrid(
                    sections: model.displayedSections,
                    selectedIDs: model.selectedIDs,
                    selectionMode: model.selectionMode,
                    gridSize: gridSize,
                    client: client,
                    thumbnails: thumbnails,
                    onOpen: onOpen,
                    onToggleSelection: { model.toggleSelection($0.id) },
                    onNearEnd: { model.loadMore(after: $0, using: client) }
                )
                .overlay(alignment: .bottom) {
                    if model.isLoadingMore { ProgressView().padding(12) }
                }
            }
        }
        .navigationTitle(model.route.title)
        .searchable(text: $model.searchText, prompt: "Search loaded photos")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.route.title)
                        .font(.headline)
                    if let dateRange {
                        Text(dateRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                gridSizeControls

                Menu {
                    Text(model.route.title).disabled(true)
                    Divider()
                    Button("Newest First") { Task { await model.refresh(using: client) } }
                    Button("Refresh") { Task { await model.refresh(using: client) } }
                } label: {
                    Label(model.route.title, systemImage: "chevron.up.chevron.down")
                }

                if model.selectionMode {
                    Text("\(model.selectedIDs.count) Selected")
                        .font(.callout.monospacedDigit())
                    Menu {
                        Button("New Album…", action: onCreateAlbum)
                            .disabled(model.selectedIDs.isEmpty)
                        if !albums.isEmpty {
                            Menu("Add to Album") {
                                ForEach(albums) { album in
                                    Button(album.albumName) { onAddToAlbum(album) }
                                }
                            }
                            .disabled(model.selectedIDs.isEmpty)
                        }
                        Divider()
                        Button("Delete from Immich", role: .destructive, action: onDelete)
                            .disabled(model.selectedIDs.isEmpty)
                    } label: {
                        Label("Selection Actions", systemImage: "ellipsis")
                    }
                    Button("Done") { model.clearSelection() }
                } else {
                    Button("Select") { model.selectionMode = true }
                }

                Menu {
                    Button(isUploading ? "Importing…" : "Import Photos…", action: onImport)
                        .disabled(isUploading)
                    Button("Refresh Library") { Task { await model.refresh(using: client) } }
                    Divider()
                    Button("Settings…", action: onSettings)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    private var gridSizeControls: some View {
        ControlGroup {
            Button { gridSize = max(100, gridSize - 10) } label: {
                Label("Smaller Photos", systemImage: "minus")
            }
            .disabled(gridSize <= 100)
            Button { gridSize = min(260, gridSize + 10) } label: {
                Label("Larger Photos", systemImage: "plus")
            }
            .disabled(gridSize >= 260)
        }
    }

    private var dateRange: String? {
        let dates = model.assets.compactMap(\.createdDate)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: first, to: last)
    }
}
