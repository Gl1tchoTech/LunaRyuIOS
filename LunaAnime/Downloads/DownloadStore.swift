//
//  DownloadStore.swift
//  LunaAnime
//
//  Observable wrapper around DownloadManager that publishes
//  progress to SwiftUI. View Models observe DownloadStore instead of
//  poking the manager directly.
//

import Foundation
import Combine

@MainActor
final class DownloadStore: ObservableObject {

    @Published private(set) var activeDownloads: [String: DownloadInfo] = [:]
    @Published private(set) var inProgressRows: [DownloadInfo] = []

    let manager: DownloadManager

    init(manager: DownloadManager) {
        self.manager = manager
    }

    // MARK: - Public API used by view models

    func download(stream: StreamSource,
                  anime: AnimeSummary,
                  episode: Episode) {
        let info = DownloadInfo(
            id: episode.id,
            animeId: episode.animeId,
            animeTitle: episode.animeTitle,
            episodeNumber: episode.number,
            season: episode.season,
            translation: episode.translation,
            state: .queued,
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: nil,
            localFileURL: nil,
            failureMessage: nil,
            queuedAt: Date()
        )
        activeDownloads[episode.id] = info
        rebuildInProgressRows()

        manager.download(
            stream: stream,
            anime: anime,
            episode: episode,
            progress: { [weak self] progress, bytes in
                guard let self = self else { return }
                self.update(episodeId: episode.id) { $0.progress = progress;
                                                    $0.bytesDownloaded = bytes;
                                                    $0.state = .downloading }
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let url):
                    self.update(episodeId: episode.id) {
                        $0.state = .completed
                        $0.progress = 1
                        $0.localFileURL = url
                        $0.totalBytes = $0.bytesDownloaded
                    }
                case .failure(let err):
                    self.update(episodeId: episode.id) {
                        $0.state = .failed
                        $0.failureMessage = err.localizedDescription
                    }
                }
            }
        )
    }

    func cancel(episodeId: String) {
        manager.cancel(episodeId: episodeId)
        activeDownloads.removeValue(forKey: episodeId)
        rebuildInProgressRows()
    }

    func isDownloading(episodeId: String) -> Bool {
        activeDownloads[episodeId] != nil
    }

    func hasLocalFile(episodeId: String) -> Bool {
        manager.hasLocalFile(episodeId: episodeId)
    }

    func localFileURL(episodeId: String, translation: Translation) -> URL? {
        manager.localFileURL(episodeId: episodeId, translation: translation)
    }

    // MARK: - Internals

    private func update(episodeId: String,
                        _ mutate: (inout DownloadInfo) -> Void) {
        guard var info = activeDownloads[episodeId] else { return }
        mutate(&info)
        activeDownloads[episodeId] = info
        rebuildInProgressRows()
    }

    private func rebuildInProgressRows() {
        inProgressRows = activeDownloads.values
            .sorted(by: { $0.queuedAt > $1.queuedAt })
    }
}
