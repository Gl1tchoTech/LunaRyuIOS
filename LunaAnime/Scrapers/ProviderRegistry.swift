//
//  ProviderRegistry.swift
//  LunaAnime
//
//  Concrete registry of every AnimeProvider the app ships with, plus
//  a circuit-breaker so a single broken provider doesn't take down the app.
//

import Foundation
import Combine

@MainActor
final class ProviderRegistry: ObservableObject {

    @Published private(set) var providers: [AnimeProvider]
    @Published var activeProviderId: String

    private let httpClient: HTTPClient
    private let preferences: UserPreferencesStore
    private let failureThreshold = 3
    private let recoveryInterval: TimeInterval = 60

    private var failureCount: [String: Int] = [:]
    private var lastFailure: [String: Date] = [:]
    private var circuitOpen: Set<String> = []

    init(providers: [AnimeProvider],
         httpClient: HTTPClient,
         preferences: UserPreferencesStore) {
        self.providers = providers
        self.httpClient = httpClient
        self.preferences = preferences
        self.activeProviderId = preferences.activeProviderId
            ?? providers.first?.id
            ?? "animepahe"
    }

    static func preconfigured(httpClient: HTTPClient,
                              preferences: UserPreferencesStore) -> ProviderRegistry {
        let providers: [AnimeProvider] = [
            AnimePaheProvider(httpClient: httpClient),
            GogoanimeProvider(httpClient: httpClient),
            HianimeProvider(httpClient: httpClient)
        ]
        let registry = ProviderRegistry(
            providers: providers,
            httpClient: httpClient,
            preferences: preferences
        )
        return registry
    }

    // MARK: - Selection

    var activeProvider: AnimeProvider? {
        providers.first { $0.id == activeProviderId }
    }

    func setActiveProvider(id: String) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeProviderId = id
        preferences.activeProviderId = id
    }

    func provider(id: String) -> AnimeProvider? {
        providers.first { $0.id == id }
    }

    // MARK: - Circuit breaker

    /// Records a successful call for a provider, closing any open circuit.
    func recordSuccess(providerId: String) {
        failureCount[providerId] = 0
        lastFailure[providerId] = nil
        circuitOpen.remove(providerId)
    }

    /// Records a failed call; opens the circuit at the threshold.
    func recordFailure(providerId: String) {
        let now = Date()
        failureCount[providerId, default: 0] += 1
        lastFailure[providerId] = now

        if (failureCount[providerId] ?? 0) >= failureThreshold {
            circuitOpen.insert(providerId)
            Log.warn(.scraper, "Circuit OPEN for provider \(providerId) after \(failureCount[providerId] ?? 0) failures.")
        }
    }

    func providerIsReachable(_ provider: AnimeProvider) -> Bool {
        if circuitOpen.contains(provider.id),
           let last = lastFailure[provider.id],
           Date().timeIntervalSince(last) >= recoveryInterval {
            // Auto half-open after recovery interval
            return true
        }
        return !circuitOpen.contains(provider.id)
    }

    /// Execute a provider call with circuit-breaker semantics.
    /// If the circuit is open and `fallback` is provided, the fallback runs.
    func execute<T>(_ operation: (AnimeProvider) async throws -> T,
                    fallback: ((AnimeProvider) async throws -> T)? = nil) async throws -> T {
        guard let active = activeProvider else { throw ProviderError.notConfigured }
        if !providerIsReachable(active) {
            Log.warn(.scraper, "Skipping provider \(active.id) — circuit open.")
            if let fallback = fallback {
                return try await fallback(active)
            }
            throw ProviderError.scrapeFailed(reason: "Provider temporarily unavailable.")
        }
        do {
            let result = try await operation(active)
            recordSuccess(providerId: active.id)
            return result
        } catch {
            recordFailure(providerId: active.id)
            if let fallback = fallback {
                return try await fallback(active)
            }
            throw error
        }
    }
}
