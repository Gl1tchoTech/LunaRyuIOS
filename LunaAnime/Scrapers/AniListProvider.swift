//
//  AniListProvider.swift
//  LunaAnime
//
//  AniList GraphQL catalogue provider. Stable, free, no auth, well-documented.
//  Returns rich anime metadata (titles, episodes, relations, characters, scores)
//  but NO streams. Marked `.catalogOnly` so the UI surfaces that distinction.
//
//  API: https://graphql.anilist.co (POST, JSON body with `query` + `variables`).
//
//  Rate-limit guidance: 90 requests/minute per IP. The default session timeout
//  (25s) is fine; we don't spam AniList.
//
//

import Foundation

final class AniListProvider: AnimeProvider, @unchecked Sendable {

    let id = "anilist"
    let displayName = "AniList (Catalogue)"
    let iconSystemName = "book.closed.fill"
    var capabilities: ProviderCapabilities {
        [.search, .detailPage, .episodeListing, .catalogOnly]
    }
    var isOperational: Bool = true

    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private let http: HTTPClient
    private let pageSize = 20

    init(httpClient: HTTPClient) {
        self.http = httpClient
    }

    // MARK: - AnimeProvider

    func fetchPopular() async throws -> [AnimeSummary] {
        let q = """
        query ($page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) {
              id
              title { romaji english }
              coverImage { large color }
              episodes
              status
              averageScore
              startDate { year }
              description
            }
          }
        }
        """
        return try await runSearch(query: q, variables: ["page": 1, "perPage": pageSize])
    }

    func fetchRecentEpisodes() async throws -> [Episode] {
        // AniList doesn't expose a true "recently aired episodes" listing,
        // so we approximate by ordering by start date descending and
        // synthesising a "Episode 1" stub for each.
        let q = """
        query ($page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            media(type: ANIME, sort: START_DATE_DESC, isAdult: false) {
              id
              title { romaji english }
              coverImage { large color }
              episodes
              status
              startDate { year }
            }
          }
        }
        """
        let items = try await runSearch(query: q, variables: ["page": 1, "perPage": pageSize])
        return items.prefix(20).map { summary in
            Episode(
                id: "\(summary.id)-episode-1",
                providerId: id,
                animeId: summary.id,
                animeTitle: summary.displayTitle,
                number: 1,
                season: 1,
                title: nil,
                thumbnailURL: summary.posterURL,
                duration: nil,
                translation: .sub,
                releasedAt: .now
            )
        }
    }

    func search(query: String) async throws -> [AnimeSummary] {
        guard !query.isEmpty else { return [] }
        let q = """
        query ($search: String, $page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            media(type: ANIME, search: $search, isAdult: false) {
              id
              title { romaji english }
              coverImage { large color }
              episodes
              status
              averageScore
              startDate { year }
              description
            }
          }
        }
        """
        return try await runSearch(
            query: q,
            variables: ["search": query, "page": 1, "perPage": pageSize]
        )
    }

    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails {
        guard let aid = Int(animeId) else {
            throw ProviderError.decode(reason: "AniList expects an integer anime id; got '\(animeId)'.")
        }
        let q = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            id
            title { romaji english }
            coverImage { large color }
            bannerImage
            episodes
            status
            averageScore
            description(asHtml: false)
            startDate { year }
            genres
            siteUrl
          }
        }
        """
        let resp = try await runGraphQL(query: q, variables: ["id": aid])
        guard let media = resp["data"]?["Media"] as? [String: Any] else {
            throw ProviderError.notFound
        }
        return parseDetails(media: media, animeId: animeId)
    }

    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub] {
        // AniList only exposes episode COUNT (no per-episode metadata at this
        // endpoint). Return synthetic stubs 1..N so the detail view can still
        // render a list. The IDs are unusable for resolveStream(); the
        // streaming provider (AnimePahe) will be selected separately.
        guard let aid = Int(animeId) else {
            throw ProviderError.unsupportedCapability
        }
        let q = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) { episodes }
        }
        """
        let resp = try await runGraphQL(query: q, variables: ["id": aid])
        let episodes = resp["data"]?["Media"]?["episodes"] as? Int ?? 0
        if episodes == 0 {
            throw ProviderError.unsupportedCapability
        }
        return (1...min(episodes, 999))
            .map { num in
                EpisodeStub(
                    id: "\(animeId)-ep-\(num)",
                    number: num,
                    title: nil,
                    thumbnailURL: nil,
                    duration: nil,
                    availableTranslations: [.sub]
                )
            }
    }

    func resolveStream(episodeId: String,
                        translation: Translation) async throws -> [StreamSource] {
        // Stream resolution is delegated to the dedicated stream provider
        // (AnimePahe). Catalogue providers do not yield playable URLs.
        throw ProviderError.unsupportedCapability
    }

    // MARK: - Internals

    private func runSearch(query: String,
                           variables: [String: Any]) async throws -> [AnimeSummary] {
        let resp = try await runGraphQL(query: query, variables: variables)
        guard let media = resp["data"]?["Page"]?["media"] as? [[String: Any]] else {
            return []
        }
        return media.compactMap { parseSummary(media: $0) }
    }

    private func runGraphQL(query: String,
                            variables: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = ["query": query, "variables": variables]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let req = HTTPRequest(
            url: endpoint,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: data
        )
        let (raw, _) = try await http.send(req)
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw ProviderError.decode(reason: "AniList did not return JSON.")
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            throw ProviderError.network(underlying: "AniList: \(errors[0]["message"] ?? "unknown error")")
        }
        return json
    }

    private func parseSummary(media: [String: Any]) -> AnimeSummary? {
        guard let mediaId = media["id"] as? Int else { return nil }
        let title = extractTitle(media: media)
        let poster = (media["coverImage"] as? [String: Any])?["large"] as? String
        let year = (media["startDate"] as? [String: Any])?["year"] as? Int
        let episodes = media["episodes"] as? Int
        let score = (media["averageScore"] as? Double).map { $0 / 10.0 }
        let status = mapStatus(media["status"] as? String)
        let synopsis = (media["description"] as? String)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return AnimeSummary(
            id: String(mediaId),
            providerId: self.id,
            title: title,
            alternateTitle: nil,
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: nil,
            year: year,
            episodeCount: episodes,
            type: .tv,
            rating: score,
            status: status,
            genres: [],
            synopsis: synopsis
        )
    }

    private func parseDetails(media: [String: Any], animeId: String) -> AnimeDetails {
        let title = extractTitle(media: media)
        let poster = (media["coverImage"] as? [String: Any])?["large"] as? String
        let backdrop = media["bannerImage"] as? String
        let synopsis = (media["description"] as? String)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let year = (media["startDate"] as? [String: Any])?["year"] as? Int
        let episodes = media["episodes"] as? Int ?? 0
        let score = (media["averageScore"] as? Double).map { $0 / 10.0 }
        let status = mapStatus(media["status"] as? String)
        let genres = (media["genres"] as? [String]) ?? []
        let stubs: [EpisodeStub] = episodes > 0
            ? (1...min(episodes, 999)).map { num in
                EpisodeStub(
                    id: "\(animeId)-ep-\(num)",
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
            alternateTitle: nil,
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: backdrop.flatMap(URL.init(string:)),
            synopsis: synopsis,
            year: year,
            type: .tv,
            status: status,
            rating: score,
            genres: genres,
            episodes: stubs
        )
    }

    private func extractTitle(media: [String: Any]) -> String {
        let t = media["title"] as? [String: Any]
        return (t?["english"] as? String)
            ?? (t?["romaji"] as? String)
            ?? "Unknown"
    }

    private func mapStatus(_ raw: String?) -> AnimeStatus? {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "releasing":           return .ongoing
        case "finished":            return .completed
        case "not_yet_released":    return .upcoming
        case "hiatus":              return .hiatus
        case "cancelled":           return .unknown
        default:                    return .unknown
        }
    }
}
