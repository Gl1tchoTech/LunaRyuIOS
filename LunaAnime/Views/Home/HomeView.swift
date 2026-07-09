//
//  HomeView.swift
//  LunaAnime
//
//  Home tab. Trending row, recently added list, sticky search bar.
//

import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var scraperRegistry: ProviderRegistry
    @StateObject private var vm: HomeViewModel

    @State private var path = NavigationPath()

    init() {
        // Registry is injected via @EnvironmentObject at runtime; we re-seed
        // lazily in `.task`.
        _vm = StateObject(wrappedValue: HomeViewModel(registry: AppEnvironment.live.scraperRegistry))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TopBarView(
                    title: "LunaAnime",
                    subtitle: nil,
                    searchText: $vm.searchQuery
                )
                if vm.errorMessage != nil {
                    errorBanner
                }
                if vm.searchQuery.count >= 2 {
                    searchResults
                } else {
                    trendingRow
                    recentList
                }
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationBarHidden(true)
        .task { await vm.loadAll() }
        .refreshable { await vm.loadAll() }
        .navigationDestination(for: AnimeSummary.self) { anime in
            AnimeDetailView(anime: anime)
        }
    }

    private var errorBanner: some View {
        Text(vm.errorMessage ?? "")
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.danger)
            .padding(.horizontal, 16)
    }

    // MARK: - Trending

    private var trendingRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Trending now")
            if vm.popular.isEmpty {
                if vm.isLoadingPopular {
                    ProgressView().tint(Theme.Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    emptyRow()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.popular, id: \.id) { anime in
                            NavigationLink(value: anime) {
                                AnimeCard(anime: anime,
                                          trailingBadge: anime.type.displayName)
                                    .frame(width: Theme.Layout.posterWidth)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func emptyRow() -> some View {
        EmptyStateView(systemImage: "sparkles.tv",
                       title: "Nothing trending yet",
                       message: "Check your internet connection or switch providers in Settings.")
            .frame(height: 160)
    }

    // MARK: - Recent

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recently updated")
            if vm.recent.isEmpty {
                EmptyStateView(systemImage: "clock",
                               title: "No recent episodes",
                               message: "Check back soon or browse what's popular.")
                    .frame(minHeight: 120)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(vm.recent.prefix(8), id: \.id) { ep in
                        HStack(spacing: 12) {
                            AsyncPosterImage(url: ep.thumbnailURL)
                                .frame(width: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ep.animeTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                    .lineLimit(1)
                                Text("Episode \(ep.number) · \(ep.translation.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.Palette.textMuted)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Search

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Results")
            if vm.isLoadingSearch {
                ProgressView().tint(Theme.Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if vm.searchResults.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass",
                               title: "No matches",
                               message: "Try a different keyword or provider.")
                    .frame(minHeight: 120)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(vm.searchResults, id: \.id) { anime in
                        NavigationLink(value: anime) {
                            AnimeRow(anime: anime,
                                     subtitle: anime.synopsis.map { String($0.prefix(80)) })
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}
