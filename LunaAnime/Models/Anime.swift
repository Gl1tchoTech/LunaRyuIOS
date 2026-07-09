//
//  Anime.swift
//  LunaAnime
//
//  Domain models. These are pure value types used by views, view models,
//  scrapers and persistence. Core Data entities are mapped to/from these.
//

import Foundation

// MARK: - Anime summary (search / row results)

struct AnimeSummary: Identifiable, Hashable, Codable, Sendable {
    let id: String              // provider-scoped anime id (alphanumeric)
    let providerId: String      // which provider it came from
    let title: String
    let alternateTitle: String?
    let posterURL: URL?
    let backdropURL: URL?
    let year: Int?
    let episodeCount: Int?
    let type: AnimeType
    let rating: Double?         // 0–10
    let status: AnimeStatus?
    let genres: [String]
    let synopsis: String?

    var displayTitle: String { alternateTitle?.nilIfEmpty ?? title }
}

// MARK: - Anime details (fetched when opening detail page)

struct AnimeDetails: Identifiable, Hashable, Sendable {
    let id: String
    let providerId: String
    let title: String
    let alternateTitle: String?
    let posterURL: URL?
    let backdropURL: URL?
    let synopsis: String?
    let year: Int?
    let type: AnimeType
    let status: AnimeStatus
    let rating: Double?
    let genres: [String]
    let episodes: [EpisodeStub]   // list of all episodes across sub/dub
}

struct EpisodeStub: Identifiable, Hashable, Sendable {
    let id: String                  // provider-scoped episode id
    let number: Int                 // human-readable episode number
    let title: String?
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let availableTranslations: [Translation]
}

// MARK: - Anime Type / Status

enum AnimeType: String, Codable, Sendable, CaseIterable {
    case tv, movie, ova, ona, special, music, unknown

    var displayName: String {
        switch self {
        case .tv:      return "TV"
        case .movie:   return "Movie"
        case .ova:     return "OVA"
        case .ona:     return "ONA"
        case .special: return "Special"
        case .music:   return "Music"
        case .unknown: return "Unknown"
        }
    }
}

enum AnimeStatus: String, Codable, Sendable, CaseIterable {
    case ongoing, completed, upcoming, hiatus, unknown

    var displayName: String {
        switch self {
        case .ongoing:   return "Ongoing"
        case .completed: return "Completed"
        case .upcoming:  return "Upcoming"
        case .hiatus:    return "On Hiatus"
        case .unknown:   return "Unknown"
        }
    }

    var triColor: String {
        switch self {
        case .ongoing:   return "success"
        case .completed: return "secondary"
        case .upcoming:  return "warning"
        case .hiatus:    return "warning"
        case .unknown:   return "muted"
        }
    }
}
