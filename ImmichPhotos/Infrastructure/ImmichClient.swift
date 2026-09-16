import Foundation

struct ImmichClient: Sendable {
    struct AssetPage: Sendable {
        let assets: [ImmichAsset]
        let nextPage: Int?
    }

    enum ClientError: LocalizedError {
        case invalidServerURL
        case badResponse(Int)
        case invalidResponse
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidServerURL: "The server URL is invalid."
            case .badResponse(let code): "Immich returned HTTP \(code)."
            case .invalidResponse: "Immich returned an unexpected response."
            case .decoding(let detail): "Immich returned an asset response this version of the app couldn’t read (\(detail))."
            }
        }
    }

    let baseURL: URL
    let apiKey: String

    init?(serverURL: String, apiKey: String) {
        var value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty else { return nil }
        if !value.hasSuffix("/api") { value += "/api" }
        guard let url = URL(string: value), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else { return nil }
        self.baseURL = url
        self.apiKey = apiKey
    }

    func checkConnection() async throws {
        let (_, response) = try await URLSession.shared.data(for: request("albums"))
        try validate(response, accepted: [200])
    }

    func albums() async throws -> [ImmichAlbum] {
        let (data, response) = try await URLSession.shared.data(for: request("albums"))
        try validate(response, accepted: [200])
        return try JSONDecoder().decode([ImmichAlbum].self, from: data)
            .sorted { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }
    }

    func assets(route: LibraryRoute, page: Int, size: Int = 180) async throws -> AssetPage {
        var body: [String: Any] = [
            "page": page,
            "size": size,
            "order": "desc",
            "withDeleted": false,
        ]
        switch route {
        case .library:
            body["visibility"] = "timeline"
        case .favorites:
            body["isFavorite"] = true
            body["visibility"] = "timeline"
        case .videos:
            body["type"] = "VIDEO"
            body["visibility"] = "timeline"
        case .archived:
            body["visibility"] = "archive"
        case .locked:
            body["visibility"] = "locked"
        case .person(let person):
            body["personIds"] = [person.id]
            body["visibility"] = "timeline"
        case .people:
            throw ClientError.invalidResponse
        case .places:
            throw ClientError.invalidResponse
        case .album(let album):
            body["albumIds"] = [album.id]
        }
        return try await search(body)
    }

    func people() async throws -> [ImmichPerson] {
        let (data, response) = try await URLSession.shared.data(for: request("people"))
        try validate(response, accepted: [200])
        let decoded = try JSONDecoder().decode(ImmichPeopleResponse.self, from: data)
        return decoded.people
            .filter { ($0.isHidden ?? false) == false && !($0.name ?? "").isEmpty }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func personThumbnail(id: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request("people/\(id)/thumbnail"))
        try validate(response, accepted: 200...299)
        return data
    }

    /// A bounded map feed. It intentionally loads only the newest 540 timeline assets
    /// with EXIF data rather than materializing a large server library in memory.
    func locationAssets() async throws -> [ImmichAsset] {
        var collected: [ImmichAsset] = []
        var page = 1
        for _ in 0..<3 {
            let result = try await search([
                "visibility": "timeline",
                "withExif": true,
                "page": page,
                "size": 180,
                "order": "desc",
                "withDeleted": false,
            ])
            collected.append(contentsOf: result.assets)
            guard let next = result.nextPage else { break }
            page = next
        }
        return collected
    }

    func thumbnail(id: String, preview: Bool = false) async throws -> Data {
        let size = preview ? "preview" : "thumbnail"
        let (data, response) = try await URLSession.shared.data(for: request("assets/\(id)/thumbnail?size=\(size)"))
        try validate(response, accepted: 200...299)
        return data
    }

    func downloadOriginal(id: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request("assets/\(id)/original"))
        try validate(response, accepted: 200...299)
        return data
    }

    func videoPlaybackResource(id: String) -> (url: URL, headers: [String: String]) {
        (url("assets/\(id)/video/playback"), ["x-api-key": apiKey])
    }

    func updateAsset(id: String, isFavorite: Bool? = nil, isArchived: Bool? = nil) async throws {
        var body: [String: Any] = [:]
        if let isFavorite { body["isFavorite"] = isFavorite }
        if let isArchived { body["isArchived"] = isArchived }
        var req = request("assets/\(id)")
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response, accepted: 200...299)
    }

    func deleteAssets(ids: [String]) async throws {
        var req = request("assets")
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["ids": ids, "force": false])
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response, accepted: [204])
    }

    func createAlbum(name: String, assetIDs: [String]) async throws -> ImmichAlbum {
        var req = request("albums")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["albumName": name, "assetIds": assetIDs])
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response, accepted: 200...299)
        return try JSONDecoder().decode(ImmichAlbum.self, from: data)
    }

    func addToAlbum(id: String, assetIDs: [String]) async throws {
        var req = request("albums/\(id)/assets")
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["assetIds": assetIDs])
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response, accepted: 200...299)
    }

    func upload(fileURL: URL) async throws {
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let date = (attributes?[.modificationDate] as? Date) ?? Date()
        let timestamp = ISO8601DateFormatter.immich.string(from: date)
        let boundary = "ImmichPhotos-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("deviceAssetId", UUID().uuidString)
        field("deviceId", Host.current().localizedName ?? "Immich Photos for macOS")
        field("fileCreatedAt", timestamp)
        field("fileModifiedAt", timestamp)
        field("isFavorite", "false")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"assetData\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = request("assets")
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response, accepted: 200...299)
    }

    private func search(_ body: [String: Any]) async throws -> AssetPage {
        var req = request("search/metadata")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response, accepted: [200])
        let decoded: ImmichSearchResponse
        do {
            decoded = try JSONDecoder().decode(ImmichSearchResponse.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw ClientError.decoding("missing \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(_, context) {
            throw ClientError.decoding("unexpected type at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw ClientError.decoding("invalid JSON")
        }
        let next = decoded.assets.nextPage.flatMap(Int.init)
        return AssetPage(assets: decoded.assets.items, nextPage: next)
    }

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: url(path))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 90
        return request
    }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))!
    }

    private func validate(_ response: URLResponse, accepted: some Sequence<Int>) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard accepted.contains(http.statusCode) else { throw ClientError.badResponse(http.statusCode) }
    }
}
