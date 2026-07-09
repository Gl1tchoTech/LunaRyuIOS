//
//  Provider.swift
//  LunaAnime
//
//  Provider-related enums and capability flags.
//

import Foundation

struct ProviderCapabilities: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    static let search         = ProviderCapabilities(rawValue: 1 << 0)
    static let detailPage     = ProviderCapabilities(rawValue: 1 << 1)
    static let episodeListing = ProviderCapabilities(rawValue: 1 << 2)
    static let subTranslation = ProviderCapabilities(rawValue: 1 << 3)
    static let dubTranslation = ProviderCapabilities(rawValue: 1 << 4)
    static let directDownload = ProviderCapabilities(rawValue: 1 << 5)
    /// Provider returns metadata (titles, posters, ratings) but no
    /// playable streams. UI should label these clearly so users know
    /// playback requires a stream-capable provider.
    static let catalogOnly    = ProviderCapabilities(rawValue: 1 << 6)

    static let all: ProviderCapabilities = [
        .search, .detailPage, .episodeListing,
        .subTranslation, .dubTranslation, .directDownload
    ]

    /// True if this provider cannot resolve playable streams.
    var isCatalogOnly: Bool { contains(.catalogOnly) }
