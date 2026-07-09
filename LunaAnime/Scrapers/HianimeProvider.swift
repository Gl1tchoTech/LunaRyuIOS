//
//  HianimeProvider.swift
//  LunaAnime
//
//  Hianime scraper (formerly AniWatch / Zoro). The site serves its
//  catalogue via a JSON API under /v2/… endpoints. Stream resolution
//  returns the `.m3u8` URL directly — playback can use AVPlayer (HLS)
//  and downloads use AVAssetDownloadTask for offline viewing.
//
//  Reference: github.com/TheYogMehta/StrawVerse (providers/hianime.ts).
//

import Foundation

final class HianimeProvider: AnimeProvider, @unchecked Sendable {

    let id = "hianime"
    let displayName = "Hianime"
    let iconSystemName = "bolt.fill"
    var capabilities: ProviderCapabilities {
        [.search, .detailPage, .episodeListing, .subTranslation, .dubTranslation]
    }
    var isOperational: Bool = true

    private let base = "https://hianime.to"
    private let ajaxBase = "https://hianime.to/ajax/v2"
    private let http: HTTPClient

    init(httpClient: HTTPClient) {
        self.http = httpClient
    }

    // MARK: - Public protocol

    func fetchPopular() async throws -> [AnimeSummary] {
        let url = URL(string: "\(base)/most-popular")!
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/"]))
        return extractAnchors(html: html)
            .map { summary(from: $0) }
    }

    func fetchRecentEpisodes() async throws -> [Episode] {
        let url = URL(string: "\(base)/recently-updated")!
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/"]))
        // Recent updates list shows name + episode number.
        let pattern = #"<a\s[^>]*href=\"(/watch/[^\"]+)\"[^>]*>([\s\S]*?)</a>"#
        let blocks = Parser.allMatches(of: pattern, in: html)
        return blocks.prefix(20).enumerated().map { idx, block in
            let href = Parser.firstCaptureGroup(of: "href=\"([^\"]+)\"", in: block) ?? ""
            let titleAndEp = Parser.firstCaptureGroup(
                of: ">([^<>]+?)<", in: block)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Episode"
            return Episode(
                id: href,
                providerId: id,
                animeId: extractAnimeId(fromEpisodeHref: href) ?? "",
                animeTitle: titleAndEp.split(separator: " ").dropLast().joined(separator: " "),
                number: idx + 1,
                season: 1,
                title: nil, thumbnailURL: nil, duration: nil,
                translation: .sub, releasedAt: .now
            )
        }
    }

    func search(query: String) async throws -> [AnimeSummary] {
        guard !query.isEmpty else { return [] }
        let url = URL(string: "\(base)/search?keyword=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/"]))
        return extractAnchors(html: html)
            .map { summary(from: $0) }
    }

    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails {
        // Pretty page
        let url = URL(string: "\(base)/watch/\(animeId)")!
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/"]))
        return try parseDetailPage(html: html, animeId: animeId)
    }

    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub] {
        // AJAX endpoint: /ajax/v2/episode/list/<animeId>
        let url = URL(string: "\(ajaxBase)/episode/list/\(animeId)")!
        let html = try await http.text(HTTPRequest(url: url,
                                                   headers: ["Referer": base + "/",
                                                             "X-Requested-With": "XMLHttpRequest"]))
        let pattern = #"<a[^>]*href=\"(/watch/[^\"]+-ep-\d+)\"[^>]*data-number=\"(\d+)\"\s*>\s*([^<]+)"#
        let matches = Parser.allMatches(of: pattern, in: html)
        return matches.compactMap { block in
            guard let href = Parser.firstCaptureGroup(of: "href=\"([^\"]+)\"", in: block),
                  let num = Parser.firstCaptureGroup(of: #"data-number=\"(\d+)\""#, in: block).flatMap(Int.init)
            else { return nil }
            return EpisodeStub(
                id: href,
                number: num,
                title: Parser.firstCaptureGroup(of: ">([^<]+)<", in: block)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                thumbnailURL: nil,
                duration: nil,
                availableTranslations: [.sub, .dub]
            )
        }
    }

    func resolveStream(episodeId: String,
                              translation: Translation) async throws -> [StreamSource] {
        // Stream: /ajax/v2/episode/sources/<episodeId>
        let serverURL = URL(string: "\(ajaxBase)/episode/sources/\(episodeId)")!
        let serverJSON = try await http.text(HTTPRequest(
            url: serverURL,
            headers: ["Referer": base + "/", "X-Requested-With": "XMLHttpRequest"]
        ))
        guard let link = Parser.firstCaptureGroup(
            of: #"\"link\":\"(https?:[^\"]+)\""#,
            in: serverJSON)?
            .replacingOccurrences(of: "\\/", with: "/")
        else {
            throw ProviderError.scrapeFailed(reason: "Missing embedded link.")
        }
        let url = URL(string: link)!
        return [StreamSource(id: "\(episodeId)-stream",
                             url: url,
                             quality: nil,
                             format: .hls,
                             size: nil,
                             headers: ["Referer": base + "/"])]
    }

    // MARK: - Parsing helpers

    private struct AnchorMatch {
        let href: String
        let title: String
        let image: String?
    }

    private func extractAnchors(html: String) -> [AnchorMatch] {
        let pattern = #"<a\s[^>]*href=\"([^\"]+)\"[^>]*>([\s\S]*?)</a>"#
        let blocks = Parser.allMatches(of: pattern, in: html)
        return blocks.compactMap { block in
            guard let href = Parser.firstCaptureGroup(of: "href=\"([^\"]+)\"", in: block) else {
                return nil
            }
            let title = Parser.firstCaptureGroup(
                of: "title=\"([^\"]+)\"|>([^<>]+)<", in: block) ?? href
            let image = Parser.firstCaptureGroup(
                of: "<img[^>]*src=\"([^\"]+)\"", in: block)
            return AnchorMatch(href: href, title: title, image: image)
        }
    }

    private func summary(from anchor: AnchorMatch) -> AnimeSummary {
        let animeId = anchor.href
            .replacingOccurrences(of: "/watch/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AnimeSummary(
            id: animeId,
            providerId: id,
            title: anchor.title,
            alternateTitle: nil,
            posterURL: anchor.image.flatMap(URL.init(string:)),
            backdropURL: nil,
            year: nil, episodeCount: nil,
            type: .tv, rating: nil, status: .ongoing,
            genres: [], synopsis: nil
        )
    }

    private func parseDetailPage(html: String, animeId: String) throws -> AnimeDetails {
        let title = Parser.firstMatch(of: "<h1[^>]*>([\\s\\S]*?)</h1>", in: html)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? animeId
        let synopsis = Parser.firstMatch(of: "<div[^>]*synopsis[^>]*>([\\s\\S]*?)</div>", in: html)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let poster = Parser.attribute("src", in: html).flatMap(URL.init(string:))
        return AnimeDetails(
            id: animeId, providerId: id,
            title: title, alternateTitle: nil,
            posterURL: poster, backdropURL: nil,
            synopsis: synopsis, year: nil, type: .tv, status: .unknown,
            rating: nil, genres: [], episodes: []
        )
    }

    private func extractAnimeId(fromEpisodeHref href: String) -> String? {
        // /watch/<animeId>-ep-<n> -> <animeId>
        let pattern = "/watch/([\\w-]+?)-ep-\\d+"
        return Parser.firstCaptureGroup(of: pattern, in: href)
    }
}
