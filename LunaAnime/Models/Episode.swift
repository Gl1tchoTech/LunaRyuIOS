//
//  Episode.swift
//  LunaAnime
//
//  Episode model and related value types. Translation represents dub/sub.
//

import Foundation

// MARK: - Translation (Sub / Dub)

enum Translation: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case sub
    case dub

    var id: String { rawValue }
    var displayName: String { self == .sub ? "Subbed" : "Dubbed" }
    var shortLabel: String { self == .sub ? "SUB" : "DUB" }
}

// MARK: - Episode

/// A full episode that has been resolved from a provider.
struct Episode: Identifiable, Hashable, Sendable {
    let id: String                  // provider-scoped id
    let providerId: String
    let animeId: String
    let animeTitle: String
    let number: Int
    let season: Int
    let title: String?
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let translation: Translation
    let releasedAt: Date?

    var displayNumber: String { number.padded2 }
    var displayTitle: String { title?.nilIfEmpty ?? "Episode \(number)" }
}

// MARK: - Stream source

/// A single playable stream URL. Anime providers often return several
/// mirror qualities; we resolve them as a list and let the player choose.
struct StreamSource: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let quality: String?              // "1080p", "720p", etc.
    let format: StreamFormat
    let size: Int64?
    let headers: [String: String]?    // referer / cookie required for some hosts

    enum StreamFormat: String, Sendable, Hashable {
        case hls          // m3u8
        case mp4
        case mkv
        case unknown
    }
}
