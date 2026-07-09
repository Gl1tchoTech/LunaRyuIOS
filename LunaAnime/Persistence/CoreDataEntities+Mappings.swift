//
//  CoreDataEntities+Mappings.swift
//  LunaAnime
//
//  Mappers between the KVC-managed NSManagedObjects and our value types
//  (AnimeSummary, AnimeDetails, Episode, DownloadInfo).
//
//  Using NSManagedObject via setValue keeps this resilient to codegen
//  changes — the model XML is the source of truth, this file just
//  reads it.
//

import Foundation
import CoreData

enum EntityMapping {

    // MARK: - Anime

    static func animeValue(_ obj: NSManagedObject) -> AnimeSummary {
        AnimeSummary(
            id: obj.value(forKey: "animeId") as? String ?? "",
            providerId: obj.value(forKey: "providerId") as? String ?? "",
            title: obj.value(forKey: "title") as? String ?? "",
            alternateTitle: obj.value(forKey: "alternateTitle") as? String,
            posterURL: obj.value(forKey: "posterURL") as? URL,
            backdropURL: obj.value(forKey: "backdropURL") as? URL,
            year: obj.value(forKey: "year") as? Int,
            episodeCount: episodeCount(for: obj),
            type: AnimeType(rawValue: obj.value(forKey: "typeRaw") as? String ?? "") ?? .unknown,
            rating: nil,
            status: AnimeStatus(rawValue: obj.value(forKey: "statusRaw") as? String ?? ""),
            genres: [],
            synopsis: obj.value(forKey: "synopsis") as? String
        )
    }

    static func episodeCount(for anime: NSManagedObject) -> Int? {
        let set = anime.value(forKey: "episodes") as? NSSet
        return set?.count
    }

    // MARK: - Episode

    static func episodeValue(_ obj: NSManagedObject,
                             anime: AnimeSummary?) -> Episode {
        Episode(
            id: obj.value(forKey: "episodeId") as? String ?? "",
            providerId: (obj.value(forKey: "anime") as? NSManagedObject)?
                .value(forKey: "providerId") as? String ?? "",
            animeId: (obj.value(forKey: "anime") as? NSManagedObject)?
                .value(forKey: "animeId") as? String ?? "",
            animeTitle: (obj.value(forKey: "anime") as? NSManagedObject)?
                .value(forKey: "title") as? String ?? "",
            number: obj.value(forKey: "number") as? Int ?? 0,
            season: obj.value(forKey: "season") as? Int ?? 1,
            title: obj.value(forKey: "title") as? String,
            thumbnailURL: nil,
            duration: obj.value(forKey: "durationSeconds") as? Double,
            translation: Translation(rawValue:
                obj.value(forKey: "lastSelectedTranslationRaw") as? String ?? "sub") ?? .sub,
            releasedAt: obj.value(forKey: "lastWatched") as? Date
        )
    }

    // MARK: - Watch progress

    static func progressValue(for episode: NSManagedObject,
                              anime: AnimeSummary) -> WatchProgress? {
        let position = episode.value(forKey: "positionSeconds") as? Double ?? 0
        let duration = episode.value(forKey: "durationSeconds") as? Double ?? 0
        guard position > 1, duration > 0 else { return nil }
        let last = episode.value(forKey: "lastWatched") as? Date ?? .now
        return WatchProgress(
            episodeId: episode.value(forKey: "episodeId") as? String ?? "",
            providerId: anime.providerId,
            animeId: anime.id,
            animeTitle: anime.title,
            posterURL: anime.posterURL,
            season: episode.value(forKey: "season") as? Int ?? 1,
            episodeNumber: episode.value(forKey: "number") as? Int ?? 0,
            translation: Translation(rawValue:
                episode.value(forKey: "lastSelectedTranslationRaw") as? String ?? "sub") ?? .sub,
            positionSeconds: position,
            durationSeconds: duration,
            lastWatched: last
        )
    }

    // MARK: - Downloaded files

    static func downloadedFiles(for episode: NSManagedObject) -> [NSManagedObject] {
        let set = episode.value(forKey: "downloadedFiles") as? NSSet
        return (set?.allObjects as? [NSManagedObject]) ?? []
    }

    static func downloadInfoValue(for file: NSManagedObject,
                                  anime: AnimeSummary,
                                  episode: Episode) -> DownloadInfo {
        let localPath = file.value(forKey: "localPath") as? String ?? ""
        let url = localPath.isEmpty ? nil : URL(fileURLWithPath: localPath)
        return DownloadInfo(
            id: episode.id,
            animeId: episode.animeId,
            animeTitle: anime.title,
            episodeNumber: episode.number,
            season: episode.season,
            translation: Translation(rawValue:
                file.value(forKey: "translationRaw") as? String ?? "sub") ?? .sub,
            state: .completed,
            progress: 1,
            bytesDownloaded: file.value(forKey: "bytes") as? Int64 ?? 0,
            totalBytes: file.value(forKey: "bytes") as? Int64,
            localFileURL: url,
            failureMessage: nil,
            queuedAt: file.value(forKey: "completedAt") as? Date ?? .now
        )
    }
}
