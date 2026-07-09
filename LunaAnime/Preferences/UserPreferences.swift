//
//  UserPreferences.swift
//  LunaAnime
//
//  Stores app-level preferences. Backed by UserDefaults but isolated
//  so future migration to a different store (e.g., plist file, iCloud KV)
//  is trivial.
//

import Foundation
import Combine

@MainActor
final class UserPreferencesStore: ObservableObject {

    static let shared = UserPreferencesStore()

    private let defaults: UserDefaults

    // MARK: - Published prefs

    @Published var activeProviderId: String? {
        didSet { defaults.set(activeProviderId, forKey: Keys.activeProviderId) }
    }

    @Published var preferredTranslation: Translation {
        didSet { defaults.set(preferredTranslation.rawValue, forKey: Keys.preferredTranslation) }
    }

    @Published var preferredQuality: String? {
        didSet { defaults.set(preferredQuality, forKey: Keys.preferredQuality) }
    }

    @Published var autoDownloadNextEpisode: Bool {
        didSet { defaults.set(autoDownloadNextEpisode, forKey: Keys.autoDownloadNext) }
    }

    @Published var downloadOverCellular: Bool {
        didSet { defaults.set(downloadOverCellular, forKey: Keys.downloadOverCellular) }
    }

    @Published var showNSFWContent: Bool {
        didSet { defaults.set(showNSFWContent, forKey: Keys.showNSFW) }
    }

    @Published var lastPlayedEpisodeId: String? {
        didSet { defaults.set(lastPlayedEpisodeId, forKey: Keys.lastPlayedEpisodeId) }
    }

    enum Keys {
        static let activeProviderId      = "pref.activeProviderId"
        static let preferredTranslation  = "pref.preferredTranslation"
        static let preferredQuality      = "pref.preferredQuality"
        static let autoDownloadNext      = "pref.autoDownloadNext"
        static let downloadOverCellular  = "pref.downloadOverCellular"
        static let showNSFW              = "pref.showNSFW"
        static let lastPlayedEpisodeId   = "pref.lastPlayedEpisodeId"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.activeProviderId = defaults.string(forKey: Keys.activeProviderId)
        self.preferredTranslation = Translation(rawValue:
            defaults.string(forKey: Keys.preferredTranslation) ?? "") ?? .sub
        self.preferredQuality = defaults.string(forKey: Keys.preferredQuality)
        self.autoDownloadNextEpisode = defaults.object(forKey: Keys.autoDownloadNext) as? Bool ?? true
        self.downloadOverCellular = defaults.object(forKey: Keys.downloadOverCellular) as? Bool ?? false
        self.showNSFWContent = defaults.bool(forKey: Keys.showNSFW)
        self.lastPlayedEpisodeId = defaults.string(forKey: Keys.lastPlayedEpisodeId)
    }
}
