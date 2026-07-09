//
//  ProviderRegistry.swift
//  LunaAnime
//
//  Concrete registry of every AnimeProvider the app ships with, plus a
//  circuit-breaker so a single broken provider doesn't take down the app.
//
//  v2 (2026): Gogoanime / Hianime removed (both endpoints defunct in 2026).
//  Replaced with three stable catalog-only metadata providers (AniList via
//  GraphQL, JIKAN v4 over MAL, Kitsu REST) plus AnimePahe as the single
//  experimental stream source.
//
//

import Foundation
import Combine

@MainActor
final class ProviderRegistry: ObservableObject {

    @Published private(set) var providers: [any AnimeProvider]
    @Published var activeProviderId: String
    /// Provider ids that have failed a recent ping and should be surfaced
    /// as unavailable in the Settings UI. The full list of providers
    /// remains selectable, but the user gets a "Currently unavailable" pill.
    @Published private(set) var unavailable: Set<String> = []

    private let httpClient: HTTPClient
    private let preferences: UserPreferencesStore
    private let failureThreshold = 3
    private let recoveryInterval: TimeInterval = 60

    private var failureCount: [String: Int] = [:]
    private var lastFailure: [String: Date] = [:]
    private var circuitOpen: Set<String> = []
    private var pingTask: Task<Void, Never>?

    init(providers: [any AnimeProvider],
         httpClient: HTTPClient,
         preferences: UserPreferencesStore) {
        self.providers = providers
        self.httpClient = httpClient
        self.preferences = preferences
        self.activeProviderId = preferences.activeProviderId
            ?? providers.first?.id
            ?? "anilist"
    }

    static func preconfigured(httpClient: HTTPClient,
                              preferences: UserPreferencesStore) -> ProviderRegistry {
        let providers: [any AnimeProvider] = [
            AniListProvider(httpClient: httpClient),
            JIKANProvider(httpClient: httpClient),
            KitsuProvider(httpClient: httpClient),
            AnimePaheProvider(httpClient: httpClient)
        ]
        let registry = ProviderRegistry(
            providers: providers,
            httpClient: httpClient,
            preferences: preferences
        )
        registry.runStartupPings()
        return registry
    }

    // MARK: - Selection

    var activeProvider: (any AnimeProvider)? {
        providers.first { $0.id == activeProviderId }
    }

    func setActiveProvider(id: String) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeProviderId = id
        preferences.activeProviderId = id
    }

    func provider(id: String) -> (any AnimeProvider)? {
        providers.first { $0.id == id }
    }

    func isAvailable(_ provider: any AnimeProvider) -> Bool {
        !unavailable.contains(provider.id)
    }

    // MARK: - Startup ping

    /// At app launch, fire a single non-blocking ping against every
    /// provider. Successful pings clear any prior unavailability; failed
    /// pings add the provider to the `unavailable` set so Settings can
    /// badge it.
    func runStartupPings() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            guard let self else { return }
            // Snapshot to avoid Sendable warnings about capturing self.
            let snapshot = self.providers
            await withTaskGroup(of: (String, Bool).self) { group in
                for provider in snapshot {
                    group.addTask { (provider.id, await provider.ping()) }
                }
                for await (id, ok) in group {
                    await MainActor.run {
                        if ok {
                            self.unavailable.remove(id)
                        } else {
                            self.unavailable.insert(id)
                            Log.warn(.scraper, "Startup ping failed for provider \(id).")
                        }
                    }
                }
            }
        }
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
            unavailable.insert(providerId)
            Log.warn(.scraper, "Circuit OPEN for provider \(providerId) after \(failureCount[providerId] ?? 0) failures.")
        }
    }

    func providerIsReachable(_ provider: any AnimeProvider) -> Bool {
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
    func execute<T>(_ operation: (any AnimeProvider) async throws -> T,
                    fallback: ((any AnimeProvider) async throws -> T)? = nil) async throws -> T {
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
