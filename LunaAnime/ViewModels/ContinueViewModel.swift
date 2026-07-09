//
//  ContinueViewModel.swift
//  LunaAnime
//
//  Continue Watching tab. Lists anime with any progress > 0 and
//  surfaces the next-up episode. Honors the `isHiddenFromContinue`
//  soft-delete flag.
//

import Foundation
import CoreData
import Combine

@MainActor
final class ContinueViewModel: ObservableObject {

    struct Row: Identifiable, Hashable {
        let id: String
        let anime: AnimeSummary
        let nextEpisode: EpisodeStub?
        let progress: WatchProgress?
    }

    @Published private(set) var rows: [Row] = []

    private let persistence: PersistenceController
    private let registry: ProviderRegistry

    init(persistence: PersistenceController, registry: ProviderRegistry) {
        self.persistence = persistence
        self.registry = registry
    }

    func reload() {
        let ctx = persistence.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "Anime")
        req.predicate = NSPredicate(format: "isHiddenFromContinue == NO OR isHiddenFromContinue == nil")
        let animes = (try? ctx.fetch(req)) ?? []
        var rows: [Row] = []

        for case let anime as NSManagedObject in animes {
            let set = anime.value(forKey: "episodes") as? NSSet
            let episodes = (set?.allObjects as? [NSManagedObject]) ?? []
            // Pick the most recently watched episode with progress > 0.
            let progressEpisodes = episodes.compactMap { ep -> (NSManagedObject, WatchProgress)? in
                let pos = ep.value(forKey: "positionSeconds") as? Double ?? 0
                let dur = ep.value(forKey: "durationSeconds") as? Double ?? 0
                let last = ep.value(forKey: "lastWatched") as? Date
                guard pos > 1, dur > 0, last != nil else { return nil }
                let animeSummary = EntityMapping.animeValue(anime)
                let progress = EntityMapping.progressValue(for: ep, anime: animeSummary)
                return progress.map { (ep, $0) }
            }
            guard let next = progressEpisodes.sorted(by: {
                ($0.1.lastWatched) > ($1.1.lastWatched)
            }).first else { continue }
            let summary = EntityMapping.animeValue(anime)
            let epStub = EpisodeStub(
                id: next.0.value(forKey: "episodeId") as? String ?? "",
                number: next.0.value(forKey: "number") as? Int ?? 0,
                title: next.0.value(forKey: "title") as? String,
                thumbnailURL: nil,
                duration: next.0.value(forKey: "durationSeconds") as? Double,
                availableTranslations: [.sub]
            )
            rows.append(Row(
                id: "\(summary.providerId):\(summary.id)",
                anime: summary,
                nextEpisode: epStub,
                progress: next.1
            ))
        }
        rows.sort { ($0.progress?.lastWatched ?? .distantPast) > ($1.progress?.lastWatched ?? .distantPast) }
        self.rows = rows
    }

    func hideFromContinue(_ row: Row) {
        let ctx = persistence.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "Anime")
        req.predicate = NSPredicate(format: "providerId == %@ AND animeId == %@",
                                    row.anime.providerId, row.anime.id)
        req.fetchLimit = 1
        guard let anime = (try? ctx.fetch(req))?.first else { return }
        anime.setValue(true, forKey: "isHiddenFromContinue")
        try? ctx.save()
        reload()
    }

    func unhideAll() {
        let ctx = persistence.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "Anime")
        req.predicate = NSPredicate(format: "isHiddenFromContinue == YES")
        let animes = (try? ctx.fetch(req)) ?? []
        for anime in animes {
            anime.setValue(false, forKey: "isHiddenFromContinue")
        }
        try? ctx.save()
        reload()
    }
}
