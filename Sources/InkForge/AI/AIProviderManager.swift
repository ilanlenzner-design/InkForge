import Foundation

class AIProviderManager {

    static let shared = AIProviderManager()

    private(set) var providers: [AIProvider] = []
    private let defaults = UserDefaults.standard
    private let keyPrefix = "ai.apikey."

    private init() {
        providers = [
            GeminiProvider(),
            ReplicateProvider(),
        ]
    }

    // MARK: - API Key Storage

    func setAPIKey(_ key: String, for providerName: String) {
        if key.isEmpty {
            defaults.removeObject(forKey: keyPrefix + providerName)
        } else {
            defaults.set(key, forKey: keyPrefix + providerName)
        }
    }

    func apiKey(for providerName: String) -> String? {
        defaults.string(forKey: keyPrefix + providerName)
    }

    // MARK: - Provider Lookup

    func bestProvider(for mode: AIMode) -> AIProvider? {
        providers.first { provider in
            provider.supportedModes.contains(mode) && apiKey(for: provider.name) != nil
        }
    }

    func allProviders(for mode: AIMode) -> [AIProvider] {
        providers.filter { provider in
            provider.supportedModes.contains(mode) && apiKey(for: provider.name) != nil
        }
    }

    func allProvidersIncludingUnconfigured(for mode: AIMode) -> [AIProvider] {
        providers.filter { $0.supportedModes.contains(mode) }
    }
}
