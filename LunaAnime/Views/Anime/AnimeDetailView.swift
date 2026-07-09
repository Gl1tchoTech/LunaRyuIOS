//
//  AnimeDetailView.swift
//  LunaAnime
//
//  Anime detail page with poster header, sub/dub toggle, season
//  download-all action, per-episode download and play buttons.
//

import SwiftUI

struct AnimeDetailView: View {

    let anime: AnimeSummary

    @EnvironmentObject private var scraperRegistry: ProviderRegistry
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var preferences: UserPreferencesStore
    @Environment(\.managedObjectContext) private var moc

    @StateObject private var vm: AnimeDetailViewModel
    @State private var presentedEpisode: Episode?

    init(anime: AnimeSummary) {
        self.anime = anime
        _vm = StateObject(wrappedValue: AnimeDetailViewModel(
            anime: anime,
            preferences: AppEnvironment.live.preferences,
            registry: AppEnvironment.live.scraperRegistry,
            downloads: AppEnvironment.live.downloads,
            persistence: AppEnvironment.live.persistence
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                translationBar
                actionBar
                episodeList
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: anime.type == .movie ? "film" : "tv")
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .fullScreenCover(item: $presentedEpisode) { ep in
            PlayerView(anime: anime,
                       initialEpisode: ep,
                       initialTranslation: vm.currentTranslation)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncPosterImage(url: anime.backdropURL ?? anime.posterURL,
                             aspect: Theme.Layout.backdropAspect)
                .frame(height: 260)
                .overlay(Theme.Gradients.heroOverlay)
            HStack(alignment: .bottom) {
                AsyncPosterImage(url: anime.posterURL)
                    .frame(width: 110)
                    .shadow(radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(anime.displayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    if let year = anime.year {
                        Text("\(String(year)) · \(anime.type.displayName)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if let status = anime.status {
                        statusPill(status)
                    }
                }
                .padding(.leading, 6)
                Spacer()
            }
            .padding(16)
        }
    }

    private func statusPill(_ status: AnimeStatus) -> some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }

    // MARK: - Translation bar

    private var translationBar: some View {
        HStack(spacing: 10) {
            ForEach(Translation.allCases) { t in
                Button {
                    Task { await vm.changeTranslation(t) }
                } label: {
                    Text(t.displayName)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            vm.currentTranslation == t
                            ? AnyShapeStyle(Theme.Gradients.accent)
                            : AnyShapeStyle(Theme.Palette.surfaceHigh)
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await vm.downloadAllSeason() }
            } label: {
                Label("Download season", systemImage: "arrow.down.to.line.compact")
            }
            .buttonStyle(PillButtonStyle(filled: true))

            Spacer()

            if !vm.allEpisodes.isEmpty {
                Button {
                    if let first = vm.resolvedEpisodes.first {
                        presentedEpisode = first
                    }
                } label: {
                    Label("Watch", systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle(filled: false))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Episode list

    @ViewBuilder
    private var episodeList: some View {
        if vm.isLoading {
            LoadingView(message: "Loading episodes…").frame(height: 200)
        } else if let err = vm.errorMessage {
            EmptyStateView(systemImage: "exclamationmark.triangle",
                           title: "Couldn't load this anime",
                           message: err)
                .frame(height: 200)
        } else if vm.allEpisodes.isEmpty {
            EmptyStateView(systemImage: "tray",
                           title: "No episodes found",
                           message: "Try a different provider.")
                .frame(height: 200)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(vm.allEpisodes) { stub in
                    EpisodeRow(
                        episode: stub,
                        isDownloaded: downloads.hasLocalFile(episodeId: stub.id),
                        isCurrentlyDownloading: downloads.isDownloading(episodeId: stub.id),
                        downloadProgress: nil,
                        onTap: {
                            if let ep = vm.resolvedEpisodes.first(where: { $0.id == stub.id }) {
                                presentedEpisode = ep
                            }
                        },
                        onDownload: {
                            Task { await vm.download(episodeStub: stub) }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
