import Foundation
import Observation

@MainActor @Observable
final class LibraryViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        var assets: [ImmichAsset]
    }

    private(set) var phase: Phase = .idle
    private(set) var route: LibraryRoute = .library
    private(set) var assets: [ImmichAsset] = []
    private(set) var sections: [Section] = []
    private(set) var isLoadingMore = false
    var selectedIDs = Set<String>()
    var selectionMode = false
    var searchText = ""

    private var nextPage: Int? = 1
    private var seenIDs = Set<String>()
    private var generation = 0
    private let pageSize = 180

    var selectedAssets: [ImmichAsset] { assets.filter { selectedIDs.contains($0.id) } }
    var displayedSections: [Section] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            let assets = section.assets.filter { asset in
                let location = [asset.exifInfo?.city, asset.exifInfo?.state, asset.exifInfo?.country]
                    .compactMap { $0 }.joined(separator: " ")
                return asset.originalFileName.localizedCaseInsensitiveContains(query)
                    || location.localizedCaseInsensitiveContains(query)
            }
            guard !assets.isEmpty else { return nil }
            return Section(id: section.id, title: section.title, assets: assets)
        }
    }

    func load(route: LibraryRoute, using client: ImmichClient) async {
        generation += 1
        let expected = generation
        self.route = route
        assets = []
        sections = []
        seenIDs = []
        nextPage = 1
        selectedIDs = []
        phase = .loading
        do {
            let page = try await client.assets(route: route, page: 1, size: pageSize)
            guard expected == generation else { return }
            append(page.assets, nextPage: page.nextPage)
            phase = assets.isEmpty ? .empty : .loaded
        } catch {
            guard expected == generation else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func refresh(using client: ImmichClient) async {
        await load(route: route, using: client)
    }

    func loadMore(after asset: ImmichAsset, using client: ImmichClient) {
        guard let page = nextPage, !isLoadingMore,
              assets.suffix(36).contains(asset) else { return }
        isLoadingMore = true
        let expected = generation
        let requestedRoute = route
        Task {
            defer { if expected == generation { isLoadingMore = false } }
            do {
                let result = try await client.assets(route: requestedRoute, page: page, size: pageSize)
                guard expected == generation else { return }
                append(result.assets, nextPage: result.nextPage)
            } catch { }
        }
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func clearSelection() {
        selectedIDs = []
        selectionMode = false
    }

    func replace(_ asset: ImmichAsset) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[index] = asset
        rebuildSections()
    }

    func remove(ids: Set<String>) {
        assets.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        rebuildSections()
        if assets.isEmpty { phase = .empty }
    }

    private func append(_ values: [ImmichAsset], nextPage: Int?) {
        self.nextPage = nextPage
        for asset in values where seenIDs.insert(asset.id).inserted {
            assets.append(asset)
        }
        rebuildSections()
    }

    private func rebuildSections() {
        var buckets: [String: [ImmichAsset]] = [:]
        for asset in assets {
            let key = asset.fileCreatedAt.map { String($0.prefix(7)) } ?? "unknown"
            buckets[key, default: []].append(asset)
        }
        sections = buckets.keys.sorted(by: >).map { key in
            let title: String
            if key == "unknown" { title = "Unknown Date" }
            else if let date = DateFormatter.monthKey.date(from: key + "-01") {
                title = DateFormatter.monthYear.string(from: date)
            } else { title = key }
            return Section(id: key, title: title, assets: buckets[key] ?? [])
        }
    }
}
