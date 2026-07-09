//
//  EpisodeRow.swift
//  LunaAnime
//
//  Reusable row for the episode list shown on the AnimeDetailView.
//

import SwiftUI

struct EpisodeRow: View {

    let episode: EpisodeStub
    let isDownloaded: Bool
    let isCurrentlyDownloading: Bool
    let downloadProgress: Double?
    let onTap: () -> Void
    let onDownload: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Palette.surfaceElevated)
                        .frame(width: 56, height: 56)
                    Text("\(episode.number)")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let progress = downloadProgress, isCurrentlyDownloading {
                        VStack { Spacer(); ProgressView(value: progress).tint(Theme.Palette.accent).padding(4) }
                    }
                    if isDownloaded {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Palette.success)
                                    .background(Circle().fill(.black).padding(4))
                            }
                            Spacer()
                            Text("Offline")
                                .font(.caption2.weight(.semibold))
                                .padding(4)
                                .background(.black.opacity(0.6), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(.bottom, 4)
                        }
                        .padding(2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title?.nilIfEmpty ?? "Episode \(episode.number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        ForEach(episode.availableTranslations, id: \.self) { trans in
                            Text(trans.shortLabel)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.Palette.surfaceHigh, in: Capsule())
                        }
                        if let dur = episode.duration {
                            Text(formatDuration(dur))
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
                Spacer()
                Button {
                    onDownload()
                } label: {
                    Image(systemName: isDownloaded ? "arrow.down.circle.fill" :
                                       (isCurrentlyDownloading ? "stop.circle" : "arrow.down.circle"))
                        .font(.title2)
                        .foregroundStyle(isDownloaded ? Theme.Palette.success :
                                         Theme.Palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let secs = Int(t)
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}
