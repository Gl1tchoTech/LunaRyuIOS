//
//  LibraryView.swift
//  LunaAnime
//
//  Library tab. Shows all anime with at least one downloaded episode.
//  Tap into LibraryDetailView to manage per-episode export / delete.
//

import SwiftUI

struct LibraryView: View {

    @EnvironmentObject private var downloads: DownloadStore
    @StateObject private var vm: LibraryViewModel

    init() {
        _vm = StateObject(wrappedValue: LibraryViewModel(
            persistence: AppEnvironment.live.persistence
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TopBarView(
                    title: "Library",
                    subtitle: "Watch offline · Export anywhere"
                )
                activeDownloadsSection
                if vm.rows.isEmpty {
                    EmptyStateView(
                        systemImage: "arrow.down.circle",
                        title: "No downloads yet",
                        message: "Open an anime and tap the download button on an episode."
                    )
                    .frame(minHeight: 280)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.rows) { row in
                            NavigationLink(value: row) {
                                libraryRowView(row: row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
        .refreshable { vm.reload() }
        .navigationDestination(for: LibraryViewModel.LibraryRow.self) { row in
            LibraryDetailView(row: row, vm: vm)
        }
    }

    private var activeDownloadsSection: some View {
        Group {
            if !downloads.inProgressRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In progress")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.horizontal, 16)
                    ForEach(downloads.inProgressRows) { info in
                        HStack(spacing: 12) {
                            AsyncPosterImage(url: nil).frame(width: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.animeTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text("Episode \(info.episodeNumber) · \(info.translation.shortLabel) · \(info.formattedProgress)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                ProgressView(value: info.progress).tint(Theme.Palette.accent)
                            }
                            Spacer()
                            Button {
                                downloads.cancel(episodeId: info.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Palette.danger)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func libraryRowView(row: LibraryViewModel.LibraryRow) -> some View {
        HStack(spacing: 14) {
            AsyncPosterImage(url: row.anime.posterURL)
                .frame(width: 86)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.anime.displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                Text("\(row.episodes.count) episode\(row.episodes.count == 1 ? "" : "s") · \(formatBytes(row.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                HStack(spacing: 6) {
                    ForEach(Array(Set(row.episodes.map(\.translation))).sorted(by: { $0.rawValue < $1.rawValue }),
                            id: \.self) { trans in
                        Text(trans.shortLabel)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.Palette.surfaceHigh, in: Capsule())
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .padding(12)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatBytes(_ b: Int64) -> String {
        Double(b).byteSizeFormatted
    }
}
