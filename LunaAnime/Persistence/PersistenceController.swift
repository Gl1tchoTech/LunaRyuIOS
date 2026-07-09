//
//  PersistenceController.swift
//  LunaAnime
//
//  Core Data stack. Loads LunaAnime.momd, configures merge policy and
//  exposes helpers used by view models.
//

import Foundation
import CoreData

final class PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        let modelName = "LunaAnime"
        let container = NSPersistentContainer(name: modelName)
        if inMemory, let description = container.persistentStoreDescriptions.first {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                Log.error(.persistence, "Failed to load store: \(error), \(error.userInfo)")
                #if DEBUG
                fatalError("Core Data store failed to load: \(error)")
                #endif
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container
    }

    /// Create a background context for write-heavy work (downloads, scraping).
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }

    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let ctx = newBackgroundContext()
        ctx.perform { block(ctx) }
    }

    func saveIfNeeded(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log.error(.persistence, "Save failed: \(error)")
            context.rollback()
        }
    }
}

// MARK: - Public fetch helpers

extension PersistenceController {
    /// Look up an Anime by (providerId, animeId) or insert a new one.
    @discardableResult
    func upsertAnime(providerId: String,
                     animeId: String,
                     title: String,
                     posterURL: URL? = nil,
                     backdropURL: URL? = nil,
                     in context: NSManagedObjectContext) -> NSManagedObject {
        let predicate = NSPredicate(format: "providerId == %@ AND animeId == %@", providerId, animeId)
        let request = NSFetchRequest<NSManagedObject>(entityName: "Anime")
        request.predicate = predicate
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            return existing
        }

        let anime = NSEntityDescription.insertNewObject(forEntityName: "Anime", into: context)
        anime.setValue(providerId, forKey: "providerId")
        anime.setValue(animeId, forKey: "animeId")
        anime.setValue(title, forKey: "title")
        anime.setValue(posterURL, forKey: "posterURL")
        anime.setValue(backdropURL, forKey: "backdropURL")
        anime.setValue(Date(), forKey: "addedAt")
        return anime
    }

    @discardableResult
    func upsertEpisode(anime: NSManagedObject,
                       episodeId: String,
                       season: Int,
                       number: Int,
                       title: String?,
                       duration: TimeInterval?,
                       in context: NSManagedObjectContext) -> NSManagedObject {
        let predicate = NSPredicate(format: "episodeId == %@", episodeId)
        let request = NSFetchRequest<NSManagedObject>(entityName: "Episode")
        request.predicate = predicate
        request.fetchLimit = 1
        if let existing = (try? context.fetch(request))?.first { return existing }

        let episode = NSEntityDescription.insertNewObject(forEntityName: "Episode", into: context)
        episode.setValue(episodeId, forKey: "episodeId")
        episode.setValue(season, forKey: "season")
        episode.setValue(number, forKey: "number")
        episode.setValue(title, forKey: "title")
        episode.setValue(duration ?? 0, forKey: "durationSeconds")
        episode.setValue(anime, forKey: "anime")
        return episode
    }
}
