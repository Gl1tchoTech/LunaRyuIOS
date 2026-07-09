//
//  SettingsViewModel.swift
//  LunaAnime
//
//  Settings tab. Uses ProviderRegistry + UserPreferencesStore directly.
//

import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var activeProviderId: String { didSet { applyProviderChange() } }
    @Published var preferredTranslation: Translation {
        didSet { preferences.preferredTranslation = preferredTranslation }
    }
    @Published var downloadOverCellular: Bool {
        didSet { preferences.downloadOverCellular = downloadOverCellular }
    }
    @Published var autoDownloadNextEpisode: Bool {
        didSet { preferences.autoDownloadNextEpisode = autoDownloadNextEpisode }
    }
    @Published var showNSFWContent: Bool {
        didSet { preferences.showNSFWContent = showNSFWContent }
    }
    @Published var preferredQuality: String? {
        didSet { preferences.preferredQuality = preferredQuality }
    }

    let registry: ProviderRegistry
    let preferences: UserPreferencesStore
    let availableQualityOptions = ["2160p", "1080p", "720p", "480p", "Auto"]

    init(registry: ProviderRegistry, preferences: UserPreferencesStore) {
        self.registry = registry
        self.preferences = preferences
        self.activeProviderId = preferences.activeProviderId ?? registry.activeProviderId
        self.preferredTranslation = preferences.preferredTranslation
        self.downloadOverCellular = preferences.downloadOverCellular
        self.autoDownloadNextEpisode = preferences.autoDownloadNextEpisode
        self.showNSFWContent = preferences.showNSFWContent
        self.preferredQuality = preferences.preferredQuality
    }

    private func applyProviderChange() {
        registry.setActiveProvider(id: activeProviderId)
    }
}
