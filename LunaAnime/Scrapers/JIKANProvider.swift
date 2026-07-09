//
//  JIKANProvider.swift
//  LunaAnime
//
//  JIKAN v4 — unofficial MyAnimeList REST wrapper. Stable, free, no auth.
//  Returns rich anime metadata (titles, episodes, ratings, synopses,
//  airing schedules) but NO streams. Marked `.catalogOnly`.
//
//  Rate-limit guidance: 2 requests/sec per IP. The default session timeout
//  applies on top; the abstract `ping()` keeps bursts gentle.
//
//  API: https://api.jikan.moe/v4
//

import Foundation

final class JIKANProvider: AnimeProvider, @unchecked Sendable {

    let id = "jikan"
    let displayName = "MyAnimeList (JIKAN)"
    let iconSystemName = "list.bullet.rectangle"
    var capabilities: ProviderCapabilities {
        [.search, .detailPage, .episodeListing, .catalogOnly]
    }
    var isOperational: Bool = true

    private let base = "https://api.jikan.moe/v4"
    private let http: HTTPClient

    init(httpClient: HTTPClient) {
        self.http = httpClient
    }

    // MARK: - AnimeProvider

    func fetchPopular() async throws -> [AnimeSummary] {
        // MAL "top" anime list. Default returns the all-time top.
        let url = try jikanURL(path: "/top/anime", query: [
            "type": "tv",
            "filter": "bypopularity",
            "limit": "20",
            "page": "1"
        ])
        let resp = try await http.decoded(JikanListEnvelope<JikanTopAnime>.self,
                                          from: HTTPRequest(url: url))
        return (resp.data ?? []).compactMap { summary(from: $0) }
    }

    func fetchRecentEpisodes() async throws -> [Episode] {
        // JIKAN exposes an "airing" schedule endpoint; this lists anime
        // currently airing with their next episode date.
        let url = try jikanURL(path: "/schedules", query: [
            "filter": "airing",
            "limit": "20"
        ])
        let resp = try await http.decoded(JikanListEnvelope<JikanTopAnime>.self,
                                          from: HTTPRequest(url: url))
        let summaries = (resp.data ?? []).compactMap { summary(from: $0) }
        return summaries.prefix(20).map { sum in
            Episode(
                id: "\(sum.id)-episode-1",
                providerId: id,
                animeId: sum.id,
                animeTitle: sum.displayTitle,
                number: 1,
                season: 1,
                title: nil,
                thumbnailURL: sum.posterURL,
                duration: nil,
                translation: .sub,
                releasedAt: .now
            )
        }
    }

    func search(query: String) async throws -> [AnimeSummary] {
        guard !query.isEmpty else { return [] }
        let url = try jikanURL(path: "/anime", query: [
            "q": query,
            "limit": "20",
            "sfw": "true"
        ])
        let resp = try await http.decoded(JikanListEnvelope<JikanTopAnime>.self,
                                          from: HTTPRequest(url: url))
        return (resp.data ?? []).compactMap { summary(from: $0) }
    }

    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails {
        guard let aid = Int(animeId) else {
            throw ProviderError.decode(reason: "JIKAN expects an integer mal_id; got '\(animeId)'.")
        }
        let url = try jikanURL(path: "/anime/\(aid)", query: ["full": "true"])
        let resp = try await http.decoded(JikanSingleEnvelope<JikanTopAnime>.self,
                                          from: HTTPRequest(url: url))
        guard let data = resp.data else { throw ProviderError.notFound }
        return details(from: data, animeId: animeId)
    }

    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub] {
        guard let aid = Int(animeId) else {
            throw ProviderError.unsupportedCapability
        }
        let url = try jikanURL(path: "/anime/\(aid)/episodes", query: ["page": "1"])
        let resp = try await http.decoded(JikanPaginatedEpisodeEnvelope.self,
                                          from: HTTPRequest(url: url))
        let episodes = resp.data ?? []
        guard !episodes.isEmpty else {
            throw ProviderError.unsupportedCapability
        }
        return episodes.compactMap { ep -> EpisodeStub? in
            guard let num = ep.mal_id else { return nil }
            return EpisodeStub(
                id: "\(animeId)-jikan-ep-\(num)",
                number: num,
                title: ep.title,
                thumbnailURL: nil,
                duration: ep.duration.flatMap { TimeInterval($0) },
                availableTranslations: [.sub]
            )
        }
    }

    func resolveStream(episodeId: String,
                        translation: Translation) async throws -> [StreamSource] {
        throw ProviderError.unsupportedCapability
    }

    // MARK: - Internals

    private func jikanURL(path: String, query: [String: String]) throws -> URL {
        guard var comps = URLComponents(string: base + path) else {
            throw ProviderError.network(underlying: "Bad JIKAN URL: \(base + path)")
        }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else {
            throw ProviderError.network(underlying: "Could not encode JIKAN URL query.")
        }
        return url
    }

    private func summary(from item: JikanTopAnime) -> AnimeSummary? {
        guard let malId = item.mal_id else { return nil }
        let title = item.title_english?.nilIfEmpty
            ?? item.title
            ?? "Unknown"
        let poster = (item.images?["jpg"])?["large_image_url"]
            ?? (item.images?["webp"])?["large_image_url"]
        let score = item.score
        let episodes = item.episodes
        let status = mapStatus(item.status)
        let year = item.aired?.from.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
        let synopsis = item.synopsis?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AnimeSummary(
            id: String(malId),
            providerId: id,
            title: title,
            alternateTitle: item.title_japanese,
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: nil,
            year: year,
            episodeCount: episodes,
            type: mapType(item.type),
            rating: score,
            status: status,
            genres: item.genres?.map(\.name) ?? [],
            synopsis: synopsis
        )
    }

    private func details(from item: JikanTopAnime, animeId: String) -> AnimeDetails {
        let title = item.title_english?.nilIfEmpty
            ?? item.title
            ?? animeId
        let synopsis = item.synopsis?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let poster = (item.images?["jpg"])?["large_image_url"]
        let backdrop = (item.images?["jpg"])?["large_image_url"]
        let year = item.aired?.from.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
        let stubs: [EpisodeStub] = (item.episodes ?? 0) > 0
            ? (1...min(item.episodes ?? 0, 999)).map { num in
                EpisodeStub(
                    id: "\(animeId)-jikan-ep-\(num)",
                    number: num,
                    title: nil,
                    thumbnailURL: nil,
                    duration: nil,
                    availableTranslations: [.sub]
                )
              }
            : []
        return AnimeDetails(
            id: animeId,
            providerId: id,
            title: title,
            alternateTitle: item.title_japanese,
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: backdrop.flatMap(URL.init(string:)),
            synopsis: synopsis,
            year: year,
            type: mapType(item.type),
            status: mapStatus(item.status) ?? .unknown,
            rating: item.score,
            genres: item.genres?.map(\.name) ?? [],
            episodes: stubs
        )
    }

    private func mapType(_ raw: String?) -> AnimeType {
        guard let raw = raw?.lowercased() else { return .unknown }
        switch raw {
        case "tv":        return .tv
        case "movie":     return .movie
        case "ova":       return .ova
        case "ona":       return .ona
        case "special":   return .special
        case "music":     return .music
        default:          return .unknown
        }
    }

    private func mapStatus(_ raw: String?) -> AnimeStatus? {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "airing", "currently airing":    return .ongoing
        case "finished", "complete":          return .completed
        case "not yet aired", "upcoming":      return .upcoming
        case "on hiatus":                     return .hiatus
        default:                              return .unknown
        }
    }
}

// MARK: - JSON envelope

private struct JikanListEnvelope<T: Decodable>: Decodable {
    let data: [T]?
}

private struct JikanPaginatedEpisodeEnvelope: Decodable {
    let data: [JikanEpisode]?
}

private struct JikanSingleEnvelope<T: Decodable>: Decodable {
    let data: T?
}

// MARK: - JSON shapes

private struct JikanTopAnime: Decodable {
    let mal_id: Int?
    let url: String?
    let title: String?
    let title_english: String?
    let title_japanese: String?
    let type: String?
    let episodes: Int?
    let status: String?
    let score: Double?
    let synopsis: String?
    let aired: JikanAired?
    let images: [String: [String: String]]?
    let genres: [JikanGenre]?
}

private struct JikanGenre: Decodable { let name: String }

private struct JikanAired: Decodable {
    let from: String?
    let to: String?
}

private struct JikanEpisode: Decodable {
    let mal_id: Int?
    let title: String?
    let duration: Int?
}
