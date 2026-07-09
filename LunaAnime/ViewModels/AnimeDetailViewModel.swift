//
//  AnimeDetailViewModel.swift
//  LunaAnime
//
//  Loads anime detail + episodes, supports sub/dub switching,
//  episode-level downloads, and seeds navigation into the player.
//

import Foundation
import Combine
import CoreData

@MainActor
final class AnimeDetailViewModel: ObservableObject {

    @Published private(set) var details: AnimeDetails?
    @Published private(set) var allEpisodes: [EpisodeStub] = []
    @Published private(set) var currentTranslation: Translation = .sub
    @Published private(set) var resolvedEpisodes: [Episode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isResolving = false
    @Published var errorMessage: String?

    let anime: AnimeSummary
    let preferences: UserPreferencesStore
    private let registry: ProviderRegistry
    private let downloads: DownloadStore
    private let persistence: PersistenceController

    init(anime: AnimeSummary,
         preferences: UserPreferencesStore,
         registry: ProviderRegistry,
         downloads: DownloadStore,
         persistence: PersistenceController) {
        self.anime = anime
        self.preferences = preferences
        self.registry = registry
        self.downloads = downloads
        self.persistence = persistence
        self.currentTranslation = preferences.preferredTranslation
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await registry.execute({
                try await $0.fetchAnimeDetails(animeId: self.anime.id)
            })
            details = detail
            let episodes = try await registry.execute({
                try await $0.fetchEpisodes(animeId: self.anime.id)
            })
            allEpisodes = episodes
            await resolveAllEpisodes()
        } catch let e as ProviderError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ensure each downloaded / partially watched episode exists in Core Data.
    private func resolveAllEpisodes() async {
        isResolving = true
        defer { isResolving = false }
        let moc = persistence.viewContext
        await seedAnimeAndEpisodes(moc: moc)
        let episodes: [Episode] = allEpisodes.compactMap { stub in
            Episode(
                id: stub.id,
                providerId: anime.providerId,
                animeId: anime.id,
                animeTitle: anime.title,
                number: stub.number,
                season: 1,
                title: stub.title,
                thumbnailURL: stub.thumbnailURL,
                duration: stub.duration,
                translation: currentTranslation,
                releasedAt: nil
            )
        }
        resolvedEpisodes = episodes
    }

    private func seedAnimeAndEpisodes(moc: NSManagedObjectContext) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            moc.perform {
                let anime = PersistenceController.shared.upsertAnime(
                    providerId: self.anime.providerId,
                    animeId: self.anime.id,
                    title: self.anime.title,
                    posterURL: self.anime.posterURL,
                    backdropURL: self.anime.backdropURL,
                    in: moc)
                for stub in self.allEpisodes {
                    _ = PersistenceController.shared.upsertEpisode(
                        anime: anime,
                        episodeId: stub.id,
                        season: 1,
                        number: stub.number,
                        title: stub.title,
                        duration: stub.duration,
                        in: moc)
                }
                PersistenceController.shared.saveIfNeeded(moc)
                cont.resume()
            }
        }
    }

    // MARK: - Translation

    func changeTranslation(_ t: Translation) async {
        guard t != currentTranslation else { return }
        currentTranslation = t
        await resolveAllEpisodes()
    }

    // MARK: - Downloads

    func download(episodeStub stub: EpisodeStub) async {
        do {
            let streams = try await registry.execute({
                try await $0.resolveStream(episodeId: stub.id,
                                           translation: self.currentTranslation)
            }, fallback: { _ in [] })
            guard let stream = streams.first else { return }
            let episode = Episode(
                id: stub.id, providerId: anime.providerId, animeId: anime.id,
                animeTitle: anime.title, number: stub.number, season: 1,
                title: stub.title, thumbnailURL: stub.thumbnailURL,
                duration: stub.duration, translation: currentTranslation,
                releasedAt: nil)
            downloads.download(stream: stream, anime: anime, episode: episode)
        } catch {
            Log.error(.download, "Could not resolve stream for download: \(error)")
        }
    }

    func downloadAllSeason() async {
        for stub in allEpisodes {
            await download(episodeStub: stub)
        }
    }

    // MARK: - Player entry point

    func makeEpisodeList() -> [Episode] {
        resolvedEpisodes
    }
}
