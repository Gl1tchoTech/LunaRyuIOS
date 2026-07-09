//
//  WatchProgress.swift
//  LunaAnime
//
//  WatchProgress captures where a user left off in an episode / anime.
//

import Foundation

struct WatchProgress: Codable, Hashable, Sendable {
    let episodeId: String
    let providerId: String
    let animeId: String
    let animeTitle: String
    let posterURL: URL?
    let season: Int
    let episodeNumber: Int
    let translation: Translation
    let positionSeconds: Double
    let durationSeconds: Double
    let lastWatched: Date

    /// 0...1 progress fraction.
    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return max(0, min(1, positionSeconds / durationSeconds))
    }

    var remainingSeconds: Double { max(0, durationSeconds - positionSeconds) }

    /// "x minutes left" or "almost done".
    var remainingLabel: String {
        let secs = Int(remainingSeconds)
        if secs < 30 { return "almost done" }
        let m = secs / 60
        if m < 60 { return "\(m) min left" }
        let h = m / 60
        let r = m % 60
        return "\(h)h \(r)m left"
    }
}

// MARK: - Download state

enum DownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued:        return "Queued"
        case .downloading:   return "Downloading"
        case .paused:        return "Paused"
        case .completed:     return "Completed"
        case .failed:        return "Failed"
        case .cancelled:     return "Cancelled"
        }
    }
}

struct DownloadInfo: Identifiable, Hashable, Sendable {
    let id: String                  // episodeId
    let animeId: String
    let animeTitle: String
    let episodeNumber: Int
    let season: Int
    let translation: Translation
    var state: DownloadState
    var progress: Double            // 0...1    var bytesDownloaded: Int64
        let totalBytes: Int64?
        var localFileURL: URL?
    let failureMessage: String?
    let queuedAt: Date

    var formattedProgress: String { "\(Int(progress * 100))%" }
    var formattedSize: String { Double(bytesDownloaded).byteSizeFormatted }
}
