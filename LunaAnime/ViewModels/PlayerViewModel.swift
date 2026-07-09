//
//  PlayerViewModel.swift
//  LunaAnime
//
//  SwiftUI-friendly view model for the player view. Drives stream
//  resolution, AVPlayer lifecycle, progress persistence and episode
//  navigation (prev / next).
//

import Foundation
import AVKit
import Combine
import CoreData

@MainActor
final class PlayerViewModel: ObservableObject {

    let anime: AnimeSummary
    @Published var episode: Episode
    @Published var translation: Translation

    @Published private(set) var availableTranslations: [Translation] = [.sub]
    @Published private(set) var availableStreams: [StreamSource] = []
    @Published private(set) var activeStreamURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isResolving = true
    @Published var showingError = false
    @Published var errorMessage: String?
    @Published var showChrome = true
    @Published var hasPrevious = true
    @Published var hasNext = true

    let player = AVPlayer()

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var cancellables: Set<AnyCancellable> = []
    private var episodeList: [Episode] = []
    private var currentIndex: Int = 0
    private var didAutoAdvance = false

    init(episode: Episode, translation: Translation, anime: AnimeSummary) {
        self.episode = episode
        self.translation = translation
        self.anime = anime
    }

    // MARK: - Bootstrap / streaming

    func bootstrap(downloads: DownloadStore, registry: ProviderRegistry) async {
        // Prefer a downloaded file (current translation → sub fallback).
        if let url = downloads.localFileURL(episodeId: episode.id, translation: translation) {
            activeStreamURL = url
            isResolving = false
            return
        }
        if let url = downloads.localFileURL(episodeId: episode.id, translation: .sub) {
            activeStreamURL = url
            isResolving = false
            return
        }

        await resolveStreams(registry: registry)
    }

    func changeTranslation(to t: Translation, registry: ProviderRegistry) async {
        guard t != translation else { return }
        translation = t
        await resolveStreams(registry: registry)
    }

    private func resolveStreams(registry: ProviderRegistry) async {
        isResolving = true
        activeStreamURL = nil
        defer { isResolving = false }

        do {
            let streams = try await registry.execute({ provider in
                try await provider.resolveStream(
                    episodeId: episode.id, translation: translation)
            }, fallback: { _ in
                return try await self.fallbackResolveStream(registry: registry,
                                                            translation: self.translation)
            })

            availableStreams = streams
            let chosen = pickPreferredStream(streams) ?? streams.first
            if let chosen = chosen {
                activeStreamURL = chosen.url
                attachStatusObserver()
            }
        } catch let e as ProviderError {
            errorMessage = e.errorDescription
            showingError = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func fallbackResolveStream(registry: ProviderRegistry,
                                        translation: Translation) async throws -> [StreamSource] {
        for provider in registry.providers where provider.id != registry.activeProviderId {
            do {
                return try await provider.resolveStream(
                    episodeId: episode.id, translation: translation)
            } catch {
                Log.debug(.scraper, "Fallback \(provider.id) stream resolve failed, retrying next.")
            }
        }
        throw ProviderError.notFound
    }

    private func pickPreferredStream(_ streams: [StreamSource]) -> StreamSource? {
        return streams.first(where: { $0.format == .mp4 }) ?? streams.first
    }

    // MARK: - Player lifecycle

    func play(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        attachStatusObserver()
        attachProgressObserver()
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    func toggleChrome() { showChrome.toggle() }

    private func attachStatusObserver() {
        statusObservation?.invalidate()
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) {
            [weak self] _, change in
            guard let self = self else { return }
            Task { @MainActor in
                let status = change.newValue ?? .paused
                self.isPlaying = status == .playing
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    private func attachProgressObserver() {
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        let interval = CMTime(seconds: 5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            guard let self = self else { return }
            let dur = self.player.currentItem?.duration.seconds ?? 0
            guard dur.isFinite, dur > 0 else { return }
            let progress = time.seconds / dur
            if progress >= 0.95, !self.didAutoAdvance {
                self.didAutoAdvance = true
                Task { @MainActor in
                    await self.nextEpisode(registry: AppEnvironment.live.scraperRegistry)
                }
            }
        }
    }

    // MARK: - Progress persistence

    func persistProgress(moc: NSManagedObjectContext) {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Episode")
        req.predicate = NSPredicate(format: "episodeId == %@", episode.id)
        req.fetchLimit = 1
        guard let ep = (try? moc.fetch(req))?.first,
              let dur = player.currentItem?.duration.seconds,
              dur > 0 else { return }
        ep.setValue(player.currentTime().seconds, forKey: "positionSeconds")
        ep.setValue(Date(), forKey: "lastWatched")
        ep.setValue(translation.rawValue, forKey: "lastSelectedTranslationRaw")
        try? moc.save()
    }

    // MARK: - Episode navigation

    func setEpisodeList(_ list: [Episode], currentIndex: Int) {
        self.episodeList = list
        self.currentIndex = currentIndex
        self.hasPrevious = currentIndex > 0
        self.hasNext = currentIndex < list.count - 1
    }

    func previousEpisode(registry: ProviderRegistry) async {
        guard currentIndex > 0 else { return }
        let newIndex = currentIndex - 1
        episode = episodeList[newIndex]
        currentIndex = newIndex
        hasPrevious = newIndex > 0
        hasNext = newIndex < episodeList.count - 1
        didAutoAdvance = false
        persistProgress(moc: PersistenceController.shared.viewContext)
        await resolveStreams(registry: registry)
    }

    func nextEpisode(registry: ProviderRegistry) async {
        guard currentIndex < episodeList.count - 1 else {
            didAutoAdvance = false
            return
        }
        let newIndex = currentIndex + 1
        episode = episodeList[newIndex]
        currentIndex = newIndex
        hasPrevious = newIndex > 0
        hasNext = newIndex < episodeList.count - 1
        didAutoAdvance = false
        persistProgress(moc: PersistenceController.shared.viewContext)
        await resolveStreams(registry: registry)
    }

    deinit {
        if let observer = timeObserver {
            // AVPlayer observers must be removed on the actor they were created on;
            // since player is captured by VM (main actor), this is best-effort.
            player.removeTimeObserver(observer)
        }
    }
}
