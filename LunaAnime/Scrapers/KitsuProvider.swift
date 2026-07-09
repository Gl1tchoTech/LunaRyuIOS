//
//  KitsuProvider.swift
//  LunaAnime
//
//  Kitsu REST catalogue provider. Stable, free, JSON:API compliant.
//  Returns anime metadata (titles, episodes, ratings, relationships) but
//  NO streams. Marked `.catalogOnly`.
//
//  IMPORTANT: Kitsu uses JSON:API and requires URL-escaped bracket-style
//  filter parameters (e.g. `filter[text]=naruto`). We construct those via
//  URLComponents so callers don't need to worry about escaping.
//
//  API: https://kitsu.io/api/edge
//

import Foundation

final class KitsuProvider: AnimeProvider, @unchecked Sendable {

    let id = "kitsu"
    let displayName = "Kitsu (Catalogue)"
    let iconSystemName = "tag.fill"
    var capabilities: ProviderCapabilities {
        [.search, .detailPage, .episodeListing, .catalogOnly]
    }
    var isOperational: Bool = true

    private let base = "https://kitsu.io/api/edge"
    private let http: HTTPClient

    init(httpClient: HTTPClient) {
        self.http = httpClient
    }

    // MARK: - AnimeProvider

    func fetchPopular() async throws -> [AnimeSummary] {
        let url = try kitsuURL(path: "/anime", query: [
            "page[limit]": "20",
            "sort": "-userCount"        // trending by user count
        ])
        let resp = try await http.decoded(KitsuListEnvelope<KitsuAnimeResource>.self,
                                          from: HTTPRequest(url: url))
        return (resp.data ?? []).compactMap { summary(from: $0) }
    }

    func fetchRecentEpisodes() async throws -> [Episode] {
        let url = try kitsuURL(path: "/anime", query: [
            "page[limit]": "20",
            "sort": "-startDate"
        ])
        let resp = try await http.decoded(KitsuListEnvelope<KitsuAnimeResource>.self,
                                          from: HTTPRequest(url: url))
        let items = (resp.data ?? []).compactMap { summary(from: $0) }
        return items.prefix(20).map { sum in
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
        let url = try kitsuURL(path: "/anime", query: [
            "filter[text]": query,
            "page[limit]": "20"
        ])
        let resp = try await http.decoded(KitsuListEnvelope<KitsuAnimeResource>.self,
                                          from: HTTPRequest(url: url))
        return (resp.data ?? []).compactMap { summary(from: $0) }
    }

    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails {
        let url = try kitsuURL(path: "/anime/\(animeId)", query: [:])
        let resp = try await http.decoded(KitsuSingleEnvelope<KitsuAnimeResource>.self,
                                          from: HTTPRequest(url: url))
        guard let data = resp.data else { throw ProviderError.notFound }
        return details(from: data, animeId: animeId)
    }

    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub] {
        let url = try kitsuURL(path: "/anime/\(animeId)/episodes", query: [
            "page[limit]": "50",
            "sort": "number"
        ])
        let resp = try await http.decoded(KitsuListEnvelope<KitsuEpisodeResource>.self,
                                          from: HTTPRequest(url: url))
        let episodes = resp.data ?? []
        guard !episodes.isEmpty else {
            throw ProviderError.unsupportedCapability
        }
        return episodes.compactMap { ep -> EpisodeStub? in
            let num = ep.attributes?.number ?? 0
            guard num > 0 else { return nil }
            // Kitsu episode IDs are returned as numeric suffixes on the resource URL.
            let epId = (ep.id ?? "0")
            return EpisodeStub(
                id: "\(animeId)-kitsu-ep-\(epId)",
                number: num,
                title: ep.attributes?.title,
                thumbnailURL: nil,
                duration: ep.attributes?.length.flatMap { TimeInterval($0 * 60) },
                availableTranslations: [.sub]
            )
        }
    }

    func resolveStream(episodeId: String,
                        translation: Translation) async throws -> [StreamSource] {
        throw ProviderError.unsupportedCapability
    }

    // MARK: - Internals

    private func kitsuURL(path: String, query: [String: String]) throws -> URL {
        guard var comps = URLComponents(string: base + path) else {
            throw ProviderError.network(underlying: "Bad Kitsu URL: \(base + path)")
        }
        comps.percentEncodedQuery = query
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        guard let url = comps.url else {
            throw ProviderError.network(underlying: "Could not encode Kitsu URL query.")
        }
        return url
    }

    private func summary(from resource: KitsuAnimeResource) -> AnimeSummary? {
        guard let attrs = resource.attributes, let animeId = resource.id else { return nil }
        let title = attrs.canonicalTitle
            ?? attrs.titles?.en
            ?? attrs.titles?.ja_jp
            ?? "Unknown"
        let poster = attrs.posterImage?.original
            ?? attrs.posterImage?.large
        let score = attrs.averageRating.flatMap { Double($0) }.map { $0 / 100.0 }
        let year = attrs.startDate.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
        let status = mapStatus(attrs.status)
        let synopsis = attrs.synopsis?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeCount = attrs.episodeCount
        return AnimeSummary(
            id: animeId,
            providerId: self.id,
            title: title,
            alternateTitle: attrs.titles?.en,
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: attrs.coverImage?.original.flatMap(URL.init(string:)),
            year: year,
            episodeCount: episodeCount,
            type: mapSubtype(attrs.subtype),
            rating: score,
            status: status,
            genres: [],
            synopsis: synopsis
        )
    }

    private func details(from resource: KitsuAnimeResource, animeId: String) -> AnimeDetails {
        let attrs = resource.attributes
        let title = attrs?.canonicalTitle
            ?? attrs?.titles?.en
            ?? attrs?.titles?.ja_jp
            ?? animeId
        let synopsis = attrs?.synopsis?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let poster = attrs?.posterImage?.original ?? attrs?.posterImage?.large
        let backdrop = attrs?.coverImage?.original
        let year = attrs?.startDate.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
        return AnimeDetails(
            id: animeId,
            providerId: id,
            title: title,
            alternateTitle: attrs?.titles?.en,
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: backdrop.flatMap(URL.init(string:)),
            synopsis: synopsis,
            year: year,
            type: mapSubtype(attrs?.subtype),
            status: mapStatus(attrs?.status) ?? .unknown,
            rating: attrs?.averageRating.flatMap { Double($0) }.map { $0 / 100.0 },
            genres: [],
            episodes: []
        )
    }

    private func mapSubtype(_ raw: String?) -> AnimeType {
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
        case "current":       return .ongoing
        case "finished":      return .completed
        case "upcoming":      return .upcoming
        case "tba":           return .upcoming
        case "unreleased":    return .upcoming
        default:              return nil
        }
    }
}

// MARK: - JSON envelopes (JSON:API compliant)

private struct KitsuListEnvelope<T: Decodable>: Decodable { let data: [T]? }
private struct KitsuSingleEnvelope<T: Decodable>: Decodable { let data: T? }

// MARK: - Anime resource

private struct KitsuAnimeResource: Decodable {
    let id: String?
    let attributes: KitsuAnimeAttributes?
}

private struct KitsuAnimeAttributes: Decodable {
    let slug: String?
    let canonicalTitle: String?
    let titles: KitsuTitles?
    let startDate: String?
    let endDate: String?
    let subtype: String?
    let status: String?
    let synopsis: String?
    let episodeCount: Int?
    let averageRating: String?
    let posterImage: KitsuImageSet?
    let coverImage: KitsuImageSet?
}

private struct KitsuTitles: Decodable {
    let en: String?
    let ja_jp: String?
}

private struct KitsuImageSet: Decodable {
    let tiny: String?
    let small: String?
    let medium: String?
    let large: String?
    let original: String?
}

// MARK: - Episode resource

private struct KitsuEpisodeResource: Decodable {
    let id: String?
    let attributes: KitsuEpisodeAttributes?
}

private struct KitsuEpisodeAttributes: Decodable {
    let number: Int?
    let title: String?
    let length: Int?
}
