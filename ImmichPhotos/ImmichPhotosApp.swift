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
            .frame(minWidth: 980, minHeight: 640)
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
                Text("Items move to the Immich trash according to your server's retention settings.")
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
        .windowToolbarStyle(.unified(showsTitle: false))
    }

    @ViewBuilder private func gallery(client: ImmichClient) -> some View {
        NavigationSplitView {
            Sidebar(
                route: $route,
                albums: albums,
                libraryCount: library.assets.count,
                onImport: { showImporter = true },
                onSettings: { showSettings = true },
                onSelect: { route = $0; selectedAsset = nil }
            )
            .navigationSplitViewColumnWidth(min: 210, ideal: 248, max: 320)
        } detail: {
            Group {
                if let asset = selectedAsset {
                    PhotoDetailView(
                        asset: asset,
                        client: client,
                        thumbnails: thumbnails,
                        onClose: { selectedAsset = nil },
                        onUpdated: { library.replace($0) },
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
        }
        .navigationSplitViewStyle(.balanced)
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
    let libraryCount: Int
    let onImport: () -> Void
    let onSettings: () -> Void
    let onSelect: (LibraryRoute) -> Void

    var body: some View {
        List(selection: $route) {
            Section("Library") {
                sidebarRow(.library, label: "Photos", icon: "photo.on.rectangle", badge: libraryCount > 0 ? libraryCount.formatted() : "")
                sidebarRow(.favorites, label: "Favorites", icon: "heart")
                sidebarRow(.videos, label: "Videos", icon: "play.square")
                sidebarRow(.archived, label: "Archived", icon: "archivebox")
                sidebarRow(.locked, label: "Locked", icon: "lock")
            }
            Section("Discover") {
                sidebarRow(.people, label: "People", icon: "person.2")
                sidebarRow(.places, label: "Places", icon: "map")
            }
            Section("Albums") {
                ForEach(albums) { album in
                    albumRow(album)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: onImport) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.link)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func sidebarRow(_ route: LibraryRoute, label: String, icon: String, badge: String = "") -> some View {
        // Plain Buttons: the action fires on every tap (even re-tapping
        // the active tab, e.g. to exit an open photo) while List keeps
        // native selection highlight via .tag. onTapGesture would steal
        // the click and break both.
        Button { onSelect(route) } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.plain)
        .tag(route)
        .badge(badge)
    }

    private func albumRow(_ album: ImmichAlbum) -> some View {
        Button { onSelect(.album(album)) } label: {
            Label {
                Text(album.albumName).lineLimit(1)
            } icon: {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .tag(LibraryRoute.album(album))
        .badge(album.assetCount.map { "\($0)" } ?? "")
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
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading \(model.route.title)…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView(
                    model.route.title,
                    systemImage: model.route.emptyIcon,
                    description: Text(model.route.emptyHint)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Load Photos", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh(using: client) } }
                        .buttonStyle(.borderedProminent)
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
                    if model.isLoadingMore {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading more…").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                    }
                }
                .overlay(alignment: .bottom) {
                    if model.selectionMode && !model.selectedIDs.isEmpty {
                        selectionBar
                    }
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search filename or place")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.route.title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Zoom (Photos-style: animated, stepped)
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            gridSize = max(100, gridSize - 30)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(gridSize <= 100)
                    Slider(value: zoomBinding, in: 100...260, step: 10)
                        .frame(width: 90)
                        .help("Thumbnail size")
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            gridSize = min(260, gridSize + 30)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(gridSize >= 260)
                }

                Menu {
                    Picker("Sort", selection: sortBinding) {
                        Text("Newest First").tag(true)
                        Text("Oldest First").tag(false)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort order")

                Button(model.selectionMode ? "Done" : "Select") {
                    withAnimation { model.selectionMode.toggle() }
                }
                .help("Toggle selection mode")

                Menu {
                    Button("New Album…", action: onCreateAlbum)
                    if !albums.isEmpty {
                        Menu("Add \(model.selectedIDs.count) Selected to Album") {
                            ForEach(albums) { album in
                                Button(album.albumName) { onAddToAlbum(album) }
                            }
                        }
                        .disabled(model.selectedIDs.isEmpty)
                    }
                    Divider()
                    Button(isUploading ? "Importing…" : "Import Photos…", action: onImport)
                        .disabled(isUploading)
                    Button("Refresh Library") { Task { await model.refresh(using: client) } }
                    Divider()
                    Button("Settings…", action: onSettings)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var sortBinding: Binding<Bool> {
        Binding(
            get: { model.sortNewestFirst },
            set: { model.applySort(newestFirst: $0) }
        )
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(
            get: { gridSize },
            set: { newValue in withAnimation(.easeInOut(duration: 0.22)) { gridSize = newValue } }
        )
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(model.selectedIDs.count) selected")
                .font(.callout.weight(.medium))
            Divider().frame(height: 16)
            Button("New Album…", action: onCreateAlbum)
            if !albums.isEmpty {
                Menu("Add to Album") {
                    ForEach(albums) { album in Button(album.albumName) { onAddToAlbum(album) } }
                }
            }
            Button("Delete", role: .destructive, action: onDelete)
            Button("Clear") { model.clearSelection() }
        }
        .buttonStyle(.link)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.bottom, 18)
    }

    private var subtitle: String {
        let total = model.displayedSections.reduce(0) { $0 + $1.assets.count }
        var parts: [String] = ["\(total.formatted()) \(total == 1 ? "item" : "items")"]
        if let range = dateRange { parts.append(range) }
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("filtered")
        }
        return parts.joined(separator: " · ")
    }

    private var dateRange: String? {
        let dates = model.assets.compactMap(\.createdDate).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .day) {
            return f.string(from: last)
        }
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}

private extension LibraryRoute {
    var emptyIcon: String {
        switch self {
        case .library: "photo.on.rectangle.angled"
        case .favorites: "heart"
        case .videos: "play.square"
        case .archived: "archivebox"
        case .locked: "lock"
        case .people: "person.2"
        case .places: "map"
        case .person: "person"
        case .album: "rectangle.stack"
        }
    }

    var emptyHint: String {
        switch self {
        case .library: "Import photos or choose another view."
        case .favorites: "Mark photos as favorites to find them here."
        case .videos: "Videos you upload will appear here."
        case .archived: "Archived photos stay out of your main timeline."
        case .locked: "Locked items stay on your server."
        case .people: "Name people in Immich to browse them here."
        case .places: "Photos with GPS data will appear on the map."
        case .person(let p): "No photos found for \(p.displayName)."
        case .album(let a): "“\(a.albumName)” has no photos yet. Select photos to add some."
        }
    }
}
