import Foundation
import Security
import Observation

enum KeychainStore {
    private static let service = "app.immichphotos.gallery"
    private static let account = "immich-api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CredentialError.couldNotSave
            }
        } else if status != errSecSuccess {
            throw CredentialError.couldNotSave
        }
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum CredentialError: LocalizedError {
        case couldNotSave
        var errorDescription: String? { "Couldn’t save the API key to Keychain." }
    }
}

@MainActor @Observable
final class ImmichSession {
    enum Status: Equatable {
        case needsConfiguration
        case connecting
        case connected
        case failed(String)
    }

    private(set) var serverURL: String
    private(set) var apiKey: String
    private(set) var status: Status

    init() {
        let storedURL = UserDefaults.standard.string(forKey: "immich.server-url") ?? ""
        let storedKey = KeychainStore.read() ?? ""
        serverURL = storedURL
        apiKey = storedKey
        status = storedURL.isEmpty || storedKey.isEmpty ? .needsConfiguration : .connected
    }

    var client: ImmichClient? {
        ImmichClient(serverURL: serverURL, apiKey: apiKey)
    }

    func connect(serverURL: String, apiKey: String) async -> Bool {
        status = .connecting
        guard let client = ImmichClient(serverURL: serverURL, apiKey: apiKey) else {
            status = .failed("Enter a valid server URL.")
            return false
        }
        do {
            try await client.checkConnection()
            try KeychainStore.save(apiKey)
            UserDefaults.standard.set(serverURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "immich.server-url")
            self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            self.apiKey = apiKey
            status = .connected
            return true
        } catch {
            status = .failed("Couldn’t connect. Check the server URL and API key.")
            return false
        }
    }

    func signOut() {
        KeychainStore.remove()
        UserDefaults.standard.removeObject(forKey: "immich.server-url")
        serverURL = ""
        apiKey = ""
        status = .needsConfiguration
    }
}
