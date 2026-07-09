//
//  AnimeProvider.swift
//  LunaAnime
//
//  The protocol every anime provider (AnimePahe, Gogoanime, Hianime, …)
//  conforms to. Designed so the rest of the app talks to providers
//  generically — search, browse, fetch episodes, resolve playable streams.
//

import Foundation

// MARK: - Errors

enum ProviderError: LocalizedError, Sendable {
    case notConfigured
    case unsupportedCapability
    case rateLimited(retryAfter: TimeInterval?)
    case decode(reason: String)
    case network(underlying: String)
    case scrapeFailed(reason: String)
    case layoutChanged(detail: String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This provider is not configured."
        case .unsupportedCapability:
            return "This capability is not supported by the active provider."
        case .rateLimited(let retryAfter):
            if let r = retryAfter { return "Rate-limited. Try again in \(Int(r))s." }
            return "Rate-limited. Please try again shortly."
        case .decode(let r):
            return "Failed to decode response: \(r)"
        case .network(let u):
            return "Network error: \(u)"
        case .scrapeFailed(let r):
            return "Scrape failed: \(r)"
        case .layoutChanged(let d):
            return "Anime site layout changed: \(d)"
        case .notFound:
            return "Not found."
        }
    }
}

// MARK: - Provider protocol

public protocol AnimeProvider: Identifiable, Sendable {
    /// Stable, all-lowercase id, used to persist user choice.
    var id: String { get }
    /// Display name shown in Settings.
    var displayName: String { get }
    /// SF Symbol used in Settings and badges.
    var iconSystemName: String { get }
    /// Capability flags — the app consults these instead of trying & failing.
    var capabilities: ProviderCapabilities { get }
    /// Whether the provider is currently considered operational (circuit-breaker).
    var isOperational: Bool { get }

    // MARK: Trending / discovery

    func fetchPopular() async throws -> [AnimeSummary]
    func fetchRecentEpisodes() async throws -> [Episode]

    // MARK: Search & details

    func search(query: String) async throws -> [AnimeSummary]
    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails

    /// Returns all episodes for the given translation, intermixed. Each
    /// `EpisodeStub.availableTranslations` describes which translations
    /// are actually available.
    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub]

    /// Resolve one or more playable stream URLs for the chosen translation.
    /// Returns *all* available qualities; callers can pick the best fit.
    func resolveStream(episodeId: String,
                       translation: Translation) async throws -> [StreamSource]
}

// MARK: - Default implementations

public extension AnimeProvider {
    /// Sub+both (sub always available; dub only if capability is set).
    var alwaysSupportedTranslations: [Translation] {
        var t: [Translation] = [.sub]
        if capabilities.contains(.dubTranslation) { t.append(.dub) }
        return t
    }

    func validate(_ capability: ProviderCapabilities) throws {
        guard capabilities.contains(capability) else {
            throw ProviderError.unsupportedCapability
        }
    }
}
