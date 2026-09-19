import Foundation
import Combine

/// Online AI Provider Manager — хранит несколько провайдеров (OpenAI-совместимых) в Keychain + UserDefaults.
struct OnlineProvider: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String           // "Provider 1", "Custom API"
    var baseURL: String        // https://api.openai.com/v1
    var model: String          // gpt-4o-mini, qwen/...
    var keychainKey: String    // идентификатор ключа в Keychain (per-provider)

    var displayHost: String {
        URL(string: baseURL)?.host ?? baseURL
    }
}

enum OnlineMode: String, CaseIterable, Identifiable, Codable {
    case local, online, auto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "Local AI"
        case .online: return "Online AI"
        case .auto: return "Auto"
        }
    }
    var icon: String {
        switch self {
        case .local: return "iphone"
        case .online: return "cloud"
        case .auto: return "wand.and.stars"
        }
    }
}

@MainActor
final class OnlineProviderStore: ObservableObject {
    static let shared = OnlineProviderStore()

    @Published var providers: [OnlineProvider] = [] {
        didSet { save() }
    }
    @Published var selectedId: UUID? {
        didSet { UserDefaults.standard.set(selectedId?.uuidString, forKey: "online.selectedId") }
    }
    @Published var mode: OnlineMode = OnlineMode(rawValue: UserDefaults.standard.string(forKey: "online.mode") ?? "auto") ?? .auto {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "online.mode") }
    }

    private let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("online-providers.json")
    }()

    init() {
        load()
        if let s = UserDefaults.standard.string(forKey: "online.selectedId"), let u = UUID(uuidString: s) {
            selectedId = u
        }
        if providers.isEmpty {
            // дефолтные провайдеры для первого запуска
            providers = [
                OnlineProvider(name: "Provider 1 — Hugging Face Router", baseURL: "https://router.huggingface.co/v1", model: "Qwen/Qwen2.5-7B-Instruct", keychainKey: "online.provider.1"),
                OnlineProvider(name: "Provider 2 — OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", keychainKey: "online.provider.openai"),
                OnlineProvider(name: "Custom API", baseURL: "https://api.example.com/v1", model: "custom-model", keychainKey: "online.provider.custom")
            ]
            save()
            selectedId = providers.first?.id
        }
    }

    var selected: OnlineProvider? {
        guard let id = selectedId else { return providers.first }
        return providers.first { $0.id == id } ?? providers.first
    }

    // MARK: Persistence

    private func load() {
        if let d = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([OnlineProvider].self, from: d) {
            providers = decoded
        }
    }
    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(providers) {
            try? d.write(to: storeURL, options: .atomic)
        }
    }

    // MARK: CRUD

    func add(_ p: OnlineProvider) {
        providers.append(p)
        if selectedId == nil { selectedId = p.id }
    }
    func update(_ p: OnlineProvider) {
        if let i = providers.firstIndex(where: { $0.id == p.id }) {
            providers[i] = p
        }
    }
    func delete(_ p: OnlineProvider) {
        providers.removeAll { $0.id == p.id }
        KeychainStore.deleteGeneric(key: p.keychainKey)
        if selectedId == p.id { selectedId = providers.first?.id }
    }

    // MARK: Keychain per provider

    func setKey(_ key: String, for provider: OnlineProvider) {
        KeychainStore.setGeneric(key, for: provider.keychainKey)
    }
    func getKey(for provider: OnlineProvider) -> String? {
        KeychainStore.getGeneric(key: provider.keychainKey)
    }
}

// Расширение Keychain для generic per-provider ключей
extension KeychainStore {
    static func setGeneric(_ value: String?, for account: String) -> Bool {
        guard let value, !value.isEmpty else { return deleteGeneric(key: account) }
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.aiagenthub.online",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    static func getGeneric(key account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.aiagenthub.online",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
    @discardableResult
    static func deleteGeneric(key account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.aiagenthub.online",
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
