//
//  LibraryDetailView.swift
//  LunaAnime
//
//  Per-anime library drill-down. Lists each downloaded episode with a
//  share button (exposes AirDrop, Files, VLC, etc.) and a delete action.
//

import SwiftUI

struct LibraryDetailView: View {

    let row: LibraryViewModel.LibraryRow
    @ObservedObject var vm: LibraryViewModel
    @Environment(\.managedObjectContext) private var moc

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                hero
                episodeList
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationTitle(row.anime.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete anime from Library", role: .destructive) {
                        vm.delete(row)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncPosterImage(url: row.anime.backdropURL ?? row.anime.posterURL,
                             aspect: Theme.Layout.backdropAspect)
                .frame(height: 220)
                .overlay(Theme.Gradients.heroOverlay)
            HStack(alignment: .bottom) {
                AsyncPosterImage(url: row.anime.posterURL)
                    .frame(width: 100)
                    .shadow(radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.anime.displayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(row.episodes.count) downloaded episodes · \(formatTotal())")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.leading, 6)
                Spacer()
            }
            .padding(16)
        }
    }

    private var episodeList: some View {
        VStack(spacing: 8) {
            ForEach(row.episodes) { ep in
                HStack(spacing: 12) {
                    AsyncPosterImage(url: nil).frame(width: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episode \(ep.number) · \(ep.translation.shortLabel)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(Double(ep.bytes).byteSizeFormatted)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    ShareLink(item: ep.localURL) {
                        Image(systemName: "square.and.arrow.up")
                            .padding(8)
                            .background(Theme.Palette.surfaceHigh, in: Circle())
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    Button(role: .destructive) {
                        vm.delete(episode: ep)
                    } label: {
                        Image(systemName: "trash")
                            .padding(8)
                            .background(Theme.Palette.surfaceHigh, in: Circle())
                            .foregroundStyle(Theme.Palette.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
    }

    private func formatTotal() -> String { Double(row.totalBytes).byteSizeFormatted }
}
