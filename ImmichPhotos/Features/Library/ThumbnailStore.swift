import AppKit

@MainActor
final class ThumbnailStore {
    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: Task<NSImage, Error>] = [:]

    init() { cache.countLimit = 800 }

    func image(for assetID: String, preview: Bool, client: ImmichClient) async throws -> NSImage {
        let key = "\(assetID)-\(preview ? "preview" : "thumb")"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = pending[key] { return try await task.value }
        let task = Task<NSImage, Error> {
            defer { pending[key] = nil }
            let data = try await client.thumbnail(id: assetID, preview: preview)
            try Task.checkCancellation()
            guard let image = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            cache.setObject(image, forKey: key as NSString)
            return image
        }
        pending[key] = task
        return try await task.value
    }

    func cached(_ assetID: String) -> NSImage? {
        cache.object(forKey: "\(assetID)-thumb" as NSString)
    }
}
