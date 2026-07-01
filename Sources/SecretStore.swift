import Foundation

/// Stores provider API keys in a local file (~/Library/Application Support/Kotha/keys.json).
///
/// Not the Keychain: the Keychain binds each item to the app's code signature, which
/// changes on every rebuild — so it re-prompts for the password every build. For a
/// personal, single-user app a user-only-readable file (chmod 600) is the pragmatic choice.
final class SecretStore {
    static let shared = SecretStore()

    private let store = JSONStore<[String: String]>("keys.json", ownerOnly: true)
    private var cache: [String: String]

    init() { cache = store.load() ?? [:] }

    func key(for account: String) -> String? {
        let value = cache[account]
        return (value?.isEmpty == false) ? value : nil
    }

    func hasKey(for account: String) -> Bool { key(for: account) != nil }

    func setKey(_ value: String?, for account: String) {
        if let value, !value.isEmpty { cache[account] = value } else { cache[account] = nil }
        store.save(cache)
    }
}
