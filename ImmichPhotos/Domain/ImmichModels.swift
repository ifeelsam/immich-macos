import Foundation

struct ImmichAsset: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let originalFileName: String
    let fileCreatedAt: String?
    let fileModifiedAt: String?
    var isFavorite: Bool?
    var isArchived: Bool?
    let isTrashed: Bool?
    let exifInfo: ImmichExif?

    var isVideo: Bool { type == "VIDEO" }
    var createdDate: Date? {
        ISO8601DateFormatter.immich.date(from: fileCreatedAt ?? "")
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = values.flexibleString(forKey: .type) ?? "IMAGE"
        originalFileName = values.flexibleString(forKey: .originalFileName) ?? "Untitled"
        fileCreatedAt = values.flexibleString(forKey: .fileCreatedAt)
        fileModifiedAt = values.flexibleString(forKey: .fileModifiedAt)
        isFavorite = values.flexibleBool(forKey: .isFavorite)
        isArchived = values.flexibleBool(forKey: .isArchived)
        isTrashed = values.flexibleBool(forKey: .isTrashed)
        exifInfo = try? values.decodeIfPresent(ImmichExif.self, forKey: .exifInfo)
    }
}

struct ImmichExif: Codable, Hashable, Sendable {
    let city: String?
    let state: String?
    let country: String?
    let fileSizeInByte: Int?
    let latitude: Double?
    let longitude: Double?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        city = values.flexibleString(forKey: .city)
        state = values.flexibleString(forKey: .state)
        country = values.flexibleString(forKey: .country)
        fileSizeInByte = values.flexibleInt(forKey: .fileSizeInByte)
        latitude = values.flexibleDouble(forKey: .latitude)
        longitude = values.flexibleDouble(forKey: .longitude)
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func flexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "1"].contains(value.lowercased()) ? true : ["false", "0"].contains(value.lowercased()) ? false : nil
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        return nil
    }

    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        return nil
    }

    func flexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

struct ImmichAlbum: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let albumName: String
    let assetCount: Int?
    let albumThumbnailAssetId: String?
}

struct ImmichPerson: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let numberOfAssets: Int?
    let isHidden: Bool?

    var displayName: String { (name?.isEmpty == false ? name! : "Unnamed Person") }
}

struct ImmichPeopleResponse: Codable, Sendable {
    let people: [ImmichPerson]
}

struct ImmichSearchResponse: Codable, Sendable {
    struct Assets: Codable, Sendable {
        let items: [ImmichAsset]
        let nextPage: String?
        let total: Int?
    }
    let assets: Assets
}

enum LibraryRoute: Hashable, Identifiable {
    case library
    case favorites
    case videos
    case archived
    case locked
    case people
    case places
    case person(ImmichPerson)
    case album(ImmichAlbum)

    var id: String {
        switch self {
        case .library: "library"
        case .favorites: "favorites"
        case .videos: "videos"
        case .archived: "archived"
        case .locked: "locked"
        case .people: "people"
        case .places: "places"
        case .person(let person): "person-\(person.id)"
        case .album(let album): "album-\(album.id)"
        }
    }

    var title: String {
        switch self {
        case .library: "Library"
        case .favorites: "Favorites"
        case .videos: "Videos"
        case .archived: "Archived"
        case .locked: "Locked"
        case .people: "People"
        case .places: "Places"
        case .person(let person): person.displayName
        case .album(let album): album.albumName
        }
    }
}

extension ISO8601DateFormatter {
    static let immich: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension DateFormatter {
    static let monthKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let detail: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
}
