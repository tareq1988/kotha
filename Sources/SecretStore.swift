import Foundation

/// Stores provider API keys in a local file (~/Library/Application Support/Kotha/keys.json).
///
/// Not the Keychain: the Keychain binds each item to the app's code signature, which
/// changes on every rebuild — so it re-prompts for the password every build. For a
/// personal, single-user app a user-only-readable file (chmod 600) is the pragmatic choice.
final class SecretStore {
    static let shared = SecretStore()

    private let url = AppPaths.support.appendingPathComponent("keys.json")
    private var cache: [String: String]

    init() {
        if let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        } else {
            cache = [:]
        }
    }

    func key(for account: String) -> String? {
        let value = cache[account]
        return (value?.isEmpty == false) ? value : nil
    }

    func hasKey(for account: String) -> Bool { key(for: account) != nil }

    func setKey(_ value: String?, for account: String) {
        if let value, !value.isEmpty { cache[account] = value } else { cache[account] = nil }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
