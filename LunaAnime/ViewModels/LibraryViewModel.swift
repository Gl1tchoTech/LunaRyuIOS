//
//  LibraryViewModel.swift
//  LunaAnime
//
//  Surfaces animes that have at least one downloaded episode, joined
//  with episode metadata so the Library tab can show counts, sort by
//  recency, support export per-file, and delete from disk.
//

import Foundation
import CoreData
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published private(set) var rows: [LibraryRow] = []

    struct LibraryRow: Identifiable, Hashable {
        let id: String
        let anime: AnimeSummary
        let episodes: [DownloadedEpisodeInfo]
        var totalBytes: Int64 { episodes.reduce(0) { $0 + $1.bytes } }
    }

    struct DownloadedEpisodeInfo: Identifiable, Hashable {
        let id: String          // episodeId
        let number: Int
        let translation: Translation
        let localPath: String
        let bytes: Int64
        var localURL: URL { URL(fileURLWithPath: localPath) }
    }

    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func reload() {
        let ctx = persistence.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "Anime")
        let animes = (try? ctx.fetch(req)) ?? []
        var rows: [LibraryRow] = []

        for case let anime as NSManagedObject in animes {
            let episodes = anime.value(forKey: "episodes") as? NSSet
            var infos: [DownloadedEpisodeInfo] = []
            for case let ep as NSManagedObject in (episodes ?? []) {
                let files = ep.value(forKey: "downloadedFiles") as? NSSet
                for case let f as NSManagedObject in (files ?? []) {
                    let path = f.value(forKey: "localPath") as? String ?? ""
                    guard !path.isEmpty,
                          FileManager.default.fileExists(atPath: path) else { continue }
                    let info = DownloadedEpisodeInfo(
                        id: f.objectID.uriRepresentation().absoluteString,
                        number: ep.value(forKey: "number") as? Int ?? 0,
                        translation: Translation(rawValue:
                            f.value(forKey: "translationRaw") as? String ?? "sub") ?? .sub,
                        localPath: path,
                        bytes: f.value(forKey: "bytes") as? Int64 ?? 0
                    )
                    infos.append(info)
                }
            }
            guard !infos.isEmpty else { continue }
            // Sort episodes descending by number.
            infos.sort { $0.number > $1.number }
            rows.append(LibraryRow(
                id: "\((anime.value(forKey: "providerId") as? String) ?? ""):\((anime.value(forKey: "animeId") as? String) ?? "")",
                anime: EntityMapping.animeValue(anime),
                episodes: infos
            ))
        }
        rows.sort { $0.anime.title.localizedCaseInsensitiveCompare($1.anime.title) == .orderedAscending }
        self.rows = rows
    }

    func delete(_ row: LibraryRow) {
        // Remove all downloaded files on disk.
        for ep in row.episodes {
            try? FileManager.default.removeItem(at: ep.localURL)
        }
        reload()
    }

    func delete(episode: DownloadedEpisodeInfo) {
        try? FileManager.default.removeItem(at: episode.localURL)
        reload()
    }

    /// Returns the URLs that can be shared for an episode.
    func shareURLs(for episode: DownloadedEpisodeInfo) -> [URL] {
        return [episode.localURL]
    }
}
