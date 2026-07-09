//
//  Parser.swift
//  LunaAnime
//
//  Lightweight HTML/JSON helpers used by all scrapers. We deliberately
//  avoid bundling a heavy library like SwiftSoup; enough functionality
//  is here to handle the common cases (regex extraction, encoded JSON
//  blobs, attribute scraping).
//

import Foundation

enum Parser {

    // MARK: - Regex helpers

    struct CapturedGroup {
        let value: String
        let range: NSRange
    }

    /// Capture the *first* match of `pattern` inside the input.
    static func firstMatch(of pattern: String,
                           in input: String,
                           options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        return regex.firstMatch(in: input, options: [], range: range)
            .flatMap { Range($0.range, in: input) }
            .map { String(input[$0]) }
    }

    /// Return all (non-overlapping) matches of `pattern`.
    static func allMatches(of pattern: String,
                           in input: String,
                           options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(input.startIndex..., in: input)
        return regex.matches(in: input, options: [], range: range)
            .compactMap { Range($0.range, in: input) }
            .map { String(input[$0]) }
    }

    /// Return the first captured group across all matches.
    static func firstCaptureGroup(of pattern: String,
                                  in input: String,
                                  groupIdx: Int = 1,
                                  options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range),
              groupIdx < match.numberOfRanges,
              let r = Range(match.range(at: groupIdx), in: input) else {
            return nil
        }
        return String(input[r])
    }

    static func allCaptureGroups(of pattern: String,
                                 in input: String,
                                 groupIdx: Int = 1,
                                 options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(input.startIndex..., in: input)
        return regex.matches(in: input, options: [], range: range)
            .compactMap { match -> String? in
                guard groupIdx < match.numberOfRanges,
                      let r = Range(match.range(at: groupIdx), in: input) else { return nil }
                return String(input[r])
            }
    }

    // MARK: - Attributes

    /// Extract the value of `attr="..."` from a chunk of HTML, returning the
    /// first match. Useful for `src="..."`, `href="..."`, `data-...="..."`.
    static func attribute(_ attr: String, in element: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: attr))\\s*=\\s*\"([^\"]+)\""
        return firstCaptureGroup(of: pattern, in: element)
    }

    // MARK: - Embedded JSON

    /// Many providers embed a JSON blob in a `<script id="...">...</script>`
    /// tag (NEXT_DATA, preloaded state, etc.). Extract that JSON-decodable
    /// value into a Codable type.
    static func decodedJSONBlob<T: Decodable>(scriptID: String,
                                              html: String,
                                              as type: T.Type) throws -> T {
        let pattern = "<script[^>]*id=\"\(NSRegularExpression.escapedPattern(for: scriptID))\"[^>]*>([\\s\\S]*?)</script>"
        guard let raw = firstCaptureGroup(of: pattern, in: html) else {
            throw ProviderError.scrapeFailed(reason: "Missing script id=\(scriptID).")
        }
        guard let data = raw.data(using: .utf8) else {
            throw ProviderError.decode(reason: "blob not utf8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.decode(reason: "\(scriptID) decode: \(error)")
        }
    }
}

private extension NSRegularExpression {
    static func escapedPattern(for s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }
}
