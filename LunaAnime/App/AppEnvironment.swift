//
//  AppEnvironment.swift
//  LunaAnime
//
//  Single dependency container / sandbox-everything onboarding.
//  Owns the long-lived collaborators (persistence, preferences,
//  scraper registry, download manager) and keeps them alive for the
//  lifetime of the process.
//

import Foundation
import UIKit
import Combine
import CoreData

final class AppEnvironment: ObservableObject {
    let persistence: PersistenceController
    let preferences: UserPreferencesStore
    let httpClient: HTTPClient
    let scraperRegistry: ProviderRegistry
    let downloads: DownloadStore

    private init(persistence: PersistenceController,
                 preferences: UserPreferencesStore,
                 httpClient: HTTPClient,
                 scraperRegistry: ProviderRegistry,
                 downloads: DownloadStore) {
        self.persistence = persistence
        self.preferences = preferences
        self.httpClient = httpClient
        self.scraperRegistry = scraperRegistry
        self.downloads = downloads
    }

    /// Singleton-style shared live instance produced once at app launch.
    @MainActor static let live: AppEnvironment = {
        let persistence = PersistenceController.shared
        let preferences = UserPreferencesStore.shared
        let httpClient = HTTPClient()
        let downloads = DownloadStore(manager: DownloadManager(persistence: persistence))
        let registry = ProviderRegistry.preconfigured(
            httpClient: httpClient,
            preferences: preferences
        )
        return AppEnvironment(
            persistence: persistence,
            preferences: preferences,
            httpClient: httpClient,
            scraperRegistry: registry,
            downloads: downloads
        )
   }()
}

// MARK: - Global appearance

enum AppearanceConfigurator {
    static func configureGlobalAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.Palette.background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 32, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Theme.Palette.accent)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.Palette.background.opacity(0.92))
        tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor(Theme.Palette.accent)
    }
}
