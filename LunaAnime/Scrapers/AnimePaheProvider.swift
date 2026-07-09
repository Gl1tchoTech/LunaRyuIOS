//
//  AnimePaheProvider.swift
//  LunaAnime
//
//  AnimePahe scraper. Uses the public animepahe.com JSON API exposed
//  via /api?m=… endpoints. AnimePahe's site layout has shifted in
//  the past; selectors and endpoints are isolated here so a single
//  failure can be patched without touching anything else.
//
//  Reference: github.com/SenZmaKi/Senpwai (animepahe module).
//

import Foundation

final class AnimePaheProvider: AnimeProvider, @unchecked Sendable {

    let id = "animepahe"
    let displayName = "AnimePahe"
    let iconSystemName = "sparkles"
    var capabilities: ProviderCapabilities {
        [.search, .detailPage, .episodeListing, .subTranslation, .directDownload]
    }
    var isOperational: Bool = true

    private let base = "https://animepahe.com"
    private let http: HTTPClient

    init(httpClient: HTTPClient) {
        self.http = httpClient
    }

    // MARK: - Popular / recent

    func fetchPopular() async throws -> [AnimeSummary] {
        // AnimePahe homepage JSON API: release list.
        let req = HTTPRequest(url: URL(string: "\(base)/api?m=airing&page=1")!)
        let resp = try await http.decoded(AiringResponse.self, from: req)
        return resp.data?.compactMap { self.summarize(airing: $0) } ?? []
    }

    func fetchRecentEpisodes() async throws -> [Episode] {
        let req = HTTPRequest(url: URL(string: "\(base)/api?m=airing&page=1")!)
        let airing = try await http.decoded(AiringResponse.self, from: req)
        let summaries = airing.data?.compactMap { self.summarize(airing: $0) } ?? []
        return summaries.prefix(20).map { summary in
            Episode(id: "\(summary.id)-episode-1", providerId: id,
                    animeId: summary.id, animeTitle: summary.title,
                    number: 1, season: 1, title: nil, thumbnailURL: nil,
                    duration: nil, translation: .sub, releasedAt: .now)
        }
    }

    func search(query: String) async throws -> [AnimeSummary] {
        guard !query.isEmpty else { return [] }
        let url = URL(string: "\(base)/api?m=search&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        let resp = try await http.decoded(SearchResponse.self, from: HTTPRequest(url: url))
        return resp.data?.compactMap { self.summarize(search: $0) } ?? []
    }

    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails {
        let url = URL(string: "\(base)/anime/\(animeId)")!
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/"]))
        return try parseDetailPage(html: html, animeId: animeId)
    }

    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub] {
        var page = 1
        var collected: [EpisodeStub] = []
        while true {
            let url = URL(string: "\(base)/api?m=release&id=\(animeId)&sort=episode_asc&page=\(page)")!
            let resp = try await http.decoded(ReleaseResponse.self, from: HTTPRequest(url: url))
            guard let data = resp.data, !data.isEmpty else { break }
            collected.append(contentsOf: data.compactMap { stub(release: $0) })
            page += 1
            if page > 30 { break }   // safety net
        }
        return collected
    }

    func resolveStream(episodeId: String,
                              translation: Translation) async throws -> [StreamSource] {
        // AnimePahe episode pages host "kwik.cx" iframe-style embed pages.
        // Resolution requires two HTTP hops: episode page → kwik page → final.
        guard let url = URL(string: "\(base)/play/\(episodeId)") else {
            throw ProviderError.notConfigured
        }
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/"]))
        // Extract a kwik link from the page — first match.
        guard let kwikURL = Parser.firstCaptureGroup(
            of: #"https?://kwik\.cx/[A-Za-z0-9/_-]+"#,
            in: html) else {
            throw ProviderError.scrapeFailed(reason: "No kwik link found.")
        }
        let kwikResponse = try await http.text(HTTPRequest(url: URL(string: kwikURL)!,
                                                           headers: ["Referer": base + "/"]))
        // Pull the final link — AnimePahe embeds it inside a form action / redirect chain.
        if let final = Parser.firstCaptureGroup(
            of: #"https?://[^\s"']+\.(?:m3u8|mp4)"#,
            in: kwikResponse).flatMap(URL.init(string:)) {
            let format: StreamSource.StreamFormat =
                final.pathExtension == "m3u8" ? .hls : .mp4
            return [StreamSource(id: "\(episodeId)-stream",
                                 url: final,
                                 quality: "1080p",
                                 format: format,
                                 size: nil,
                                 headers: ["Referer": kwikURL])]
        }
        throw ProviderError.scrapeFailed(reason: "Could not extract final stream URL.")
    }

    // MARK: - Parsing helpers

    private func summarize(airing row: AiringItem) -> AnimeSummary {
        AnimeSummary(
            id: row.id ?? "",
            providerId: id,
            title: row.title ?? "Unknown",
            alternateTitle: row.other_title,
            posterURL: row.poster.flatMap(URL.init(string:)),
            backdropURL: nil,
            year: row.year,
            episodeCount: row.episodes,
            type: AnimeType(rawValue: row.type?.lowercased() ?? "") ?? .tv,
            rating: nil,
            status: .ongoing,
            genres: [],
            synopsis: nil
        )
    }

    private func summarize(search row: SearchItem) -> AnimeSummary {
        AnimeSummary(
            id: row.id ?? "",
            providerId: id,
            title: row.title ?? "Unknown",
            alternateTitle: row.other_title,
            posterURL: row.poster.flatMap(URL.init(string:)),
            backdropURL: nil,
            year: row.released.flatMap { Int($0.prefix(4)) },
            episodeCount: row.episodes,
            type: AnimeType(rawValue: (row.type ?? "TV").lowercased()) ?? .tv,
            rating: row.score,
            status: AnimeStatus(rawValue: row.status?.lowercased() ?? ""),
            genres: [],
            synopsis: nil
        )
    }

    private func stub(release r: ReleaseItem) -> EpisodeStub {
        EpisodeStub(
            id: r.id ?? "",
            number: r.episode ?? 0,
            title: r.title,
            thumbnailURL: nil,
            duration: r.duration.flatMap { TimeInterval($0) },
            availableTranslations: [.sub]
        )
    }

    private func parseDetailPage(html: String, animeId: String) throws -> AnimeDetails {
        // Best-effort extraction of the synopsis + status from raw HTML.
        let synopsis = Parser.firstMatch(of: "<p>([\\s\\S]*?)</p>", in: html)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = Parser.firstMatch(of: "<h1[^>]*>([\\s\\S]*?)</h1>", in: html)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? animeId
        let poster = Parser.attribute("src",
                                      in: html.components(separatedBy: "\"poster\"").first ?? html)
            .flatMap { URL(string: $0) }
        return AnimeDetails(
            id: animeId, providerId: id,
            title: title, alternateTitle: nil,
            posterURL: poster, backdropURL: nil,
            synopsis: synopsis, year: nil, type: .tv, status: .unknown,
            rating: nil, genres: [], episodes: [])
    }
}

// MARK: - AnimePahe JSON responses

private struct AiringResponse: Decodable {
    let data: [AiringItem]?
}
private struct AiringItem: Decodable {
    let id: String?
    let title: String?
    let other_title: String?
    let poster: String?
    let year: Int?
    let episodes: Int?
    let type: String?
}

private struct SearchResponse: Decodable {
    let data: [SearchItem]?
}
private struct SearchItem: Decodable {
    let id: String?
    let title: String?
    let other_title: String?
    let poster: String?
    let released: String?
    let episodes: Int?
    let type: String?
    let score: Double?
    let status: String?
}

private struct ReleaseResponse: Decodable {
    let data: [ReleaseItem]?
}
private struct ReleaseItem: Decodable {
    let id: String?
    let episode: Int?
    let title: String?
    let duration: String?
}
