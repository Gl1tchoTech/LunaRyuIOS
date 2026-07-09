//
//  GogoanimeProvider.swift
//  LunaAnime
//
//  Gogoanime scraper. Implements HTML scraping with regex-based
//  extraction. Site uses Cloudflare-like bot detection so a custom
//  UA / Referer header is critical.
//
//  Reference: github.com/justfoolingaround/animdl (gogoanime module).
//

import Foundation

final class GogoanimeProvider: AnimeProvider, @unchecked Sendable {

    let id = "gogoanime"
    let displayName = "Gogoanime"
    let iconSystemName = "play.rectangle.fill"
    var capabilities: ProviderCapabilities {
        [.search, .detailPage, .episodeListing, .subTranslation, .dubTranslation]
    }
    var isOperational: Bool = true

    private let base = "https://gogoanime.consumet.stream"
    private let http: HTTPClient

    init(httpClient: HTTPClient) {
        self.http = httpClient
    }

    // MARK: - Public protocol

    func fetchPopular() async throws -> [AnimeSummary] {
        let html = try await http.text(HTTPRequest(
            url: URL(string: "\(base)/popular")!,
            headers: ["Referer": base + "/"]
        ))
        return extractAnchors(html: html)
            .filter { $0.href.contains("/category/") }
            .map { summary(from: $0) }
    }

    func fetchRecentEpisodes() async throws -> [Episode] {
        let html = try await http.text(HTTPRequest(
            url: URL(string: "\(base)")!,
            headers: ["Referer": base + "/"]
        ))
        // The home page has an episodes list under <ul class="items">.
        let pattern = #"<li>\s*<a href=\"([^\"]+)\">([\s\S]*?)</a>"#
        let matches = Parser.allCaptureGroups(of: pattern, in: html, groupIdx: 0)
        return matches.prefix(20).enumerated().map { idx, chunk in
            let url = Parser.firstCaptureGroup(of: "href=\"([^\"]+)\"", in: chunk) ?? ""
            let title = Parser.firstCaptureGroup(of: ">\\s*([^<>]+?)\\s*</a>", in: chunk)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Episode"
            return Episode(
                id: url.trimmingCharacters(in: .whitespacesAndNewlines),
                providerId: id,
                animeId: extractAnimeIdFromHref(url) ?? "",
                animeTitle: title,
                number: idx + 1,
                season: 1,
                title: nil,
                thumbnailURL: nil,
                duration: nil,
                translation: .sub,
                releasedAt: .now
            )
        }
    }

    func search(query: String) async throws -> [AnimeSummary] {
        guard !query.isEmpty else { return [] }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(base)/search?keyword=\(q)")!
        let html = try await http.text(HTTPRequest(url: url, headers: ["Referer": base + "/"]))
        return extractAnchors(html: html)
            .filter { $0.href.contains("/category/") }
            .map { summary(from: $0) }
    }

    func fetchAnimeDetails(animeId: String) async throws -> AnimeDetails {
        let url = URL(string: "\(base)/category/\(animeId)")!
        let html = try await http.text(HTTPRequest(url: url, headers: ["Referer": base + "/"]))
        return parseDetailPage(html: html, animeId: animeId)
    }

    func fetchEpisodes(animeId: String) async throws -> [EpisodeStub] {
        let url = URL(string: "\(base)/category/\(animeId)")!
        let html = try await http.text(HTTPRequest(url: url, headers: ["Referer": base + "/"]))
        let pattern = #"<a href=\"(/[\w-]+-episode-(\d+))\"#
        let matches = Parser.allCaptureGroups(of: pattern, in: html, groupIdx: 1)
        let numbers = Parser.allCaptureGroups(of: pattern, in: html, groupIdx: 2).compactMap(Int.init)
        return zip(matches, numbers).map { (href, num) in
            EpisodeStub(
                id: "\(animeId)-ep-\(num)",
                number: num,
                title: nil,
                thumbnailURL: nil,
                duration: nil,
                availableTranslations: [.sub, .dub]
            )
        }
    }

    func resolveStream(episodeId: String,
                              translation: Translation) async throws -> [StreamSource] {
        let url = URL(string: "\(base)/\(episodeId)")!
        let html = try await http.text(HTTPRequest(url: url, headers: ["Referer": base + "/"]))
        // Look for a server selector iframe list (Gogo typically uses multiple).
        let iframeURL = Parser.firstCaptureGroup(
            of: #"https?://[^\s"']+/streaming\.php\?id=[^\s"']+"#,
            in: html)
        guard let iframeURL = iframeURL else {
            throw ProviderError.scrapeFailed(reason: "No streaming URL on episode page.")
        }
        let embed = try await http.text(HTTPRequest(
            url: URL(string: iframeURL)!,
            headers: ["Referer": base + "/"]
        ))
        if let final = Parser.firstCaptureGroup(
            of: #"https?://[^\s"']+\.(?:m3u8|mp4)"#,
            in: embed).flatMap(URL.init(string:)) {
            let format: StreamSource.StreamFormat =
                final.pathExtension == "m3u8" ? .hls : .mp4
            return [StreamSource(id: "\(episodeId)-stream",
                                 url: final,
                                 quality: "auto",
                                 format: format,
                                 size: nil,
                                 headers: ["Referer": iframeURL])]
        }
        throw ProviderError.scrapeFailed(reason: "No final stream URL.")
    }

    // MARK: - Parsing helpers

    private struct AnchorMatch {
        let href: String
        let title: String
        let image: String?
    }

    private func extractAnchors(html: String) -> [AnchorMatch] {
        let pattern = #"<a\s+[^>]*href=\"([^\"]+)\"[^>]*>([\s\S]*?)</a>"#
        let blocks = Parser.allMatches(of: pattern, in: html)
        return blocks.compactMap { block in
            guard let href = Parser.firstCaptureGroup(of: "href=\"([^\"]+)\"", in: block)
            else { return nil }
            let title = Parser.firstCaptureGroup(
                of: "title=\"([^\"]+)\"|>([^<>]+)<", in: block) ?? href
            let image = Parser.firstCaptureGroup(
                of: "<img[^>]*src=\"([^\"]+)\"", in: block)
            return AnchorMatch(href: href, title: title, image: image)
        }
    }

    private func summary(from anchor: AnchorMatch) -> AnimeSummary {
        let animeId = anchor.href
            .replacingOccurrences(of: "/category/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AnimeSummary(
            id: animeId,
            providerId: id,
            title: anchor.title,
            alternateTitle: nil,
            posterURL: anchor.image.flatMap(URL.init(string:)),
            backdropURL: nil,
            year: nil, episodeCount: nil,
            type: .tv, rating: nil, status: nil,
            genres: [], synopsis: nil
        )
    }

    private func parseDetailPage(html: String, animeId: String) throws -> AnimeDetails {
        let title = Parser.firstMatch(of: "<h1[^>]*>([\\s\\S]*?)</h1>", in: html)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? animeId
        let synopsis = Parser.firstMatch(of: "<p[^>]*>([\\s\\S]*?)</p>", in: html)?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let poster = Parser.attribute("src", in: html).flatMap(URL.init(string:))
        return AnimeDetails(
            id: animeId, providerId: id,
            title: title, alternateTitle: nil,
            posterURL: poster, backdropURL: nil,
            synopsis: synopsis, year: nil, type: .tv, status: .unknown,
            rating: nil, genres: [],
            episodes: []
        )
    }

    private func extractAnimeIdFromHref(_ href: String) -> String? {
        let pattern = #"/category/([\w-]+)"#
        return Parser.firstCaptureGroup(of: pattern, in: href)
    }
}
