//
//  DownloadManager.swift
//  LunaAnime
//
//  Downloads episodes locally for offline use. Two parallel strategies:
//  • MP4 / direct files   → URLSession background download (resumable).
//  • HLS (.m3u8) playlists → AVAssetDownloadURLSession, which handles
//    AES-128 keys natively when the key URL is reachable. If a CDN
//    enforces strict Referer/UA on the key, headers are attached via
//    AVURLAsset's `AVURLAssetHTTPHeaderFieldsKey`.
//
//  Each completion writes a DownloadedFile row to Core Data pointing to
//  the file's local path. Read-side (Library, Player) consults those rows.
//

import Foundation
import AVFoundation
import CoreData

@MainActor
final class DownloadManager: NSObject {

    typealias ProgressHandler = (Double, Int64) -> Void
    typealias CompletionHandler = (Result<URL, Error>) -> Void

    // MARK: - State

    private let persistence: PersistenceController
    private(set) var activeTasks: [String: TaskHandle] = [:]

    /// Active direct-download tasks keyed by `URLSessionTask.taskIdentifier`.
    private var directTasks: [Int: URLSessionDownloadTask] = [:]
    /// Map direct task identifier → episodeId for lookup.
    private var directTaskToEpisode: [Int: String] = [:]
    /// Map direct task identifier → progress/completion handlers.
    private var sessionHandlers: [Int: (progress: ProgressHandler?, completion: CompletionHandler?)] = [:]

    /// Active AVAsset (HLS) download tasks keyed by episodeId.
    private var hlsTasks: [String: AVAssetDownloadTask] = [:]

    private struct TaskHandle {
        let stream: StreamSource
        let anime: AnimeSummary
        let episode: Episode
    }

    // Lazy background URLSession.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "app.lunaanime.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true   // refined via downloadOverCellular
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Lazy AVAssetDownloadSession for HLS.
    private lazy var assetDownloadSession: AVAssetDownloadURLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "app.lunaanime.hls-downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return AVAssetDownloadURLSession(configuration: config,
                                        assetDownloadDelegate: self,
                                        delegateQueue: .main)
    }()

    init(persistence: PersistenceController) {
        self.persistence = persistence
        super.init()
    }

    // MARK: - Public API

    /// Start a download for a single episode.
    func download(stream: StreamSource,
                  anime: AnimeSummary,
                  episode: Episode,
                  progress: ProgressHandler? = nil,
                  completion: CompletionHandler? = nil) {
        guard activeTasks[episode.id] == nil else { return }
        activeTasks[episode.id] = TaskHandle(stream: stream, anime: anime, episode: episode)

        switch stream.format {
        case .mp4, .mkv:
            startDirect(stream: stream, episode: episode, progress: progress, completion: completion)
        case .hls:
            startHLS(stream: stream, episode: episode, completion: completion)
        case .unknown:
            completion?(.failure(ProviderError.unsupportedCapability))
            activeTasks[episode.id] = nil
        }
    }

    /// Cancel an in-flight download by episodeId.
    func cancel(episodeId: String) {
        if let (taskId, _) = directTaskToEpisode.first(where: { $0.value == episodeId }),
           let task = directTasks[taskId] {
            task.cancel()
            cleanupDirectTask(taskId)
        }
        if let hls = hlsTasks[episodeId] {
            hls.cancel()
            hlsTasks.removeValue(forKey: episodeId)
        }
        activeTasks.removeValue(forKey: episodeId)
    }

    /// True if there is a downloaded file on disk for that episode.
    func hasLocalFile(episodeId: String) -> Bool {
        let ctx = persistence.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "Episode")
        req.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        req.fetchLimit = 1
        guard let episode = (try? ctx.fetch(req))?.first else { return false }
        let files = EntityMapping.downloadedFiles(for: episode)
        for f in files {
            if let path = f.value(forKey: "localPath") as? String,
               FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    func localFileURL(episodeId: String, translation: Translation) -> URL? {
        let ctx = persistence.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "Episode")
        req.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        req.fetchLimit = 1
        guard let episode = (try? ctx.fetch(req))?.first,
              let files = episode.value(forKey: "downloadedFiles") as? NSSet else { return nil }
        for case let f as NSManagedObject in files {
            let t = Translation(rawValue: f.value(forKey: "translationRaw") as? String ?? "") ?? .sub
            let path = f.value(forKey: "localPath") as? String ?? ""
            guard t == translation, !path.isEmpty else { continue }
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Origin folder where all downloads live (Documents/Downloads/<anime>/<episode>).
    static func downloadsRoot() -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloads = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        return downloads
    }

    // MARK: - Direct (MP4) downloads

    private func startDirect(stream: StreamSource,
                             episode: Episode,
                             progress: ProgressHandler?,
                             completion: CompletionHandler?) {
        var req = URLRequest(url: stream.url)
        if let headers = stream.headers {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }
        let task = session.downloadTask(with: req)
        let key = task.taskIdentifier
        directTasks[key] = task
        directTaskToEpisode[key] = episode.id
        sessionHandlers[key] = (progress, completion)
        task.resume()
    }

    // MARK: - HLS downloads

    private func startHLS(stream: StreamSource,
                          episode: Episode,
                          completion: CompletionHandler?) {
        var opts: [String: Any] = [:]
        if let headers = stream.headers {
            opts["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: stream.url, options: opts)

        guard let task = assetDownloadSession.makeAssetDownloadTask(
            asset: asset,
            assetTitle: episode.animeTitle,
            assetArtworkData: nil,
            options: [
                AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: NSNumber(value: 200_000)
            ]
        ) else {
            activeTasks[episode.id] = nil
            completion?(.failure(ProviderError.unsupportedCapability))
            return
        }
        hlsTasks[episode.id] = task
        task.resume()
        // Completion handler will be invoked from `completeHLS` below.
        // We stash a marker in sessionHandlers-less dict keyed by episodeId.
        hlsCompletionHandlers[episode.id] = completion
    }

    /// Map episodeId → completion for HLS downloads (no progress for HLS in this MVP).
    private var hlsCompletionHandlers: [String: CompletionHandler] = [:]

    // MARK: - Per-task cleanup

    private func cleanupDirectTask(_ taskId: Int) {
        directTasks.removeValue(forKey: taskId)
        directTaskToEpisode.removeValue(forKey: taskId)
        sessionHandlers.removeValue(forKey: taskId)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            await self.handleDirectCompletion(taskId: id, tempURL: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            self.notifyDirectProgress(taskId: id,
                                      written: totalBytesWritten,
                                      total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        Task { @MainActor in
            if let error = error as NSError? {
                self.handleDirectError(taskId: id, error: error)
            }
        }
    }
}

extension DownloadManager {
    fileprivate func notifyDirectProgress(taskId: Int, written: Int64, total: Int64) {
        guard let handler = sessionHandlers[taskId]?.progress else { return }
        let progress = total > 0 ? Double(written) / Double(total) : 0
        handler(progress, written)
    }

    fileprivate func handleDirectCompletion(taskId: Int, tempURL: URL) async {
        guard let (progress, completion) = sessionHandlers[taskId] else {
            return
        }
        guard let episodeId = directTaskToEpisode[taskId] else {
            completion?(.failure(ProviderError.notFound))
            cleanupDirectTask(taskId)
            return
        }
        do {
            let animeTitle = episodeAnimeTitle(episodeId: episodeId) ?? "anime"
            let episodeNumber = episodeNumber(episodeId: episodeId) ?? 0
            let translation = episodeLastTranslation(episodeId: episodeId) ?? .sub
            let folderURL = Self.downloadsRoot()
                .appendingPathComponent(animeTitle.folderSafe, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL,
                                                   withIntermediateDirectories: true)
            let ext = tempURL.pathExtension.isEmpty ? "mp4" : tempURL.pathExtension
            let dest = folderURL.appendingPathComponent(
                "E\(episodeNumber.padded2).\(translation.shortLabel).\(ext)"
            )
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)

            await persistDownloadedFile(episodeId: episodeId,
                                        url: dest,
                                        translation: translation,
                                        format: dest.pathExtension.lowercased())

            let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            progress?(1, Int64(size))
            completion?(.success(dest))
        } catch {
            completion?(.failure(error))
        }
        cleanupDirectTask(taskId)
    }

    fileprivate func handleDirectError(taskId: Int, error: NSError) {
        let completion = sessionHandlers[taskId]?.completion
        cleanupDirectTask(taskId)
        completion?(.failure(error))
    }

    // MARK: - Episode metadata helpers

    private func fetchEpisode(_ episodeId: String) -> NSManagedObject? {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Episode")
        req.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        req.fetchLimit = 1
        return (try? persistence.viewContext.fetch(req))?.first
    }

    private func episodeAnimeTitle(episodeId: String) -> String? {
        guard let ep = fetchEpisode(episodeId),
              let anime = ep.value(forKey: "anime") as? NSManagedObject else { return nil }
        return anime.value(forKey: "title") as? String
    }

    private func episodeNumber(episodeId: String) -> Int? {
        return fetchEpisode(episodeId)?.value(forKey: "number") as? Int
    }

    private func episodeLastTranslation(episodeId: String) -> Translation? {
        guard let ep = fetchEpisode(episodeId) else { return nil }
        return Translation(rawValue:
            ep.value(forKey: "lastSelectedTranslationRaw") as? String ?? "sub") ?? .sub
    }

    fileprivate func persistDownloadedFile(episodeId: String,
                                           url: URL,
                                           translation: Translation,
                                           format: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            persistence.performBackgroundTask { ctx in
                let req = NSFetchRequest<NSManagedObject>(entityName: "Episode")
                req.predicate = NSPredicate(format: "episodeId == %@", episodeId)
                req.fetchLimit = 1
                guard let episode = (try? ctx.fetch(req))?.first else {
                    cont.resume(); return
                }
                let file = NSEntityDescription.insertNewObject(
                    forEntityName: "DownloadedFile", into: ctx)
                file.setValue(url.path, forKey: "localPath")
                file.setValue(translation.rawValue, forKey: "translationRaw")
                file.setValue(format, forKey: "formatRaw")
                file.setValue(url.absoluteString, forKey: "sourceURLString")
                file.setValue(NSNumber(value: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                              forKey: "bytes")
                file.setValue(Date(), forKey: "completedAt")
                file.setValue(episode, forKey: "episode")
                try? ctx.save()
                cont.resume()
            }
        }
    }
}

// MARK: - AVAssetDownloadDelegate (HLS)

extension DownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,
                                assetDownloadTask: AVAssetDownloadTask,
                                didLoadTimeRange timeRange: CMTimeRange,
                                totalTimeRangesLoaded timeRanges: [NSValue],
                                timeRangeExpectedToLoad expected: CMTimeRange) {
        // Real-time HLS progress reporting could be added here.
    }

    nonisolated func urlSession(_ session: URLSession,
                                assetDownloadTask: AVAssetDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let episodeId = self.activeEpisodeId(for: assetDownloadTask)
        Task { @MainActor in
            await self.completeHLS(episodeId: episodeId, assetFolder: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.handleHLSError(error: error)
            }
        }
    }

    private func activeEpisodeId(for task: AVAssetDownloadTask) -> String {
        hlsTasks.first(where: { $0.value === task })?.key ?? ""
    }

    fileprivate func completeHLS(episodeId: String, assetFolder: URL) async {
        defer {
            hlsTasks.removeValue(forKey: episodeId)
            activeTasks.removeValue(forKey: episodeId)
        }
        let completion = hlsCompletionHandlers.removeValue(forKey: episodeId)
        guard !episodeId.isEmpty else { return }

        let title = episodeAnimeTitle(episodeId: episodeId) ?? "anime"
        let number = episodeNumber(episodeId: episodeId) ?? 0
        let translation = episodeLastTranslation(episodeId: episodeId) ?? .sub
        let folderURL = Self.downloadsRoot()
            .appendingPathComponent(title.folderSafe, isDirectory: true)
            .appendingPathComponent("E\(number.padded2).\(translation.shortLabel)", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: folderURL)
            try FileManager.default.createDirectory(at: folderURL,
                                                   withIntermediateDirectories: true)
            let contents = try FileManager.default.contentsOfDirectory(at: assetFolder,
                                                                       includingPropertiesForKeys: nil)
            for file in contents {
                let dest = folderURL.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.moveItem(at: file, to: dest)
            }
            await persistDownloadedFile(episodeId: episodeId,
                                        url: folderURL,
                                        translation: translation,
                                        format: "movpkg")
            completion?(.success(folderURL))
        } catch {
            Log.error(.download, "HLS completion failed: \(error)")
            completion?(.failure(error))
        }
    }

    fileprivate func handleHLSError(error: Error) {
        Log.error(.download, "HLS download failed: \(error.localizedDescription)")
        // We can't always pinpoint which episode failed here without extra
        // bookkeeping, but we record the error and let the user retry.
    }
}
