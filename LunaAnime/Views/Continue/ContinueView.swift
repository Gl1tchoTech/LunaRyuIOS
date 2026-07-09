//
//  ContinueView.swift
//  LunaAnime
//
//  Continue Watching tab. Lists in-progress anime with next-up info.
//  Swipe a row to remove from Continue (preserves Library).
//

import SwiftUI

struct ContinueView: View {

    @EnvironmentObject private var scraperRegistry: ProviderRegistry
    @StateObject private var vm: ContinueViewModel
    @State private var showingUnhideAlert = false

    init() {
        _vm = StateObject(wrappedValue: ContinueViewModel(
            persistence: AppEnvironment.live.persistence,
            registry: AppEnvironment.live.scraperRegistry
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TopBarView(
                    title: "Continue Watching",
                    subtitle: "Pick up where you left off",
                    trailingButton: AnyView(unhideButton)
                )
                if vm.rows.isEmpty {
                    EmptyStateView(
                        systemImage: "play.circle",
                        title: "Nothing in progress",
                        message: "Open an anime from Home to start watching."
                    )
                    .frame(minHeight: 280)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.rows) { row in
                            rowView(row: row)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        vm.hideFromContinue(row)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
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
        .alert("Show hidden entries?",
               isPresented: $showingUnhideAlert) {
            Button("Show all", action: { vm.unhideAll() })
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore every anime you previously hid from Continue.")
        }
        .navigationDestination(for: AnimeSummary.self) { anime in
            AnimeDetailView(anime: anime)
        }
    }

    private var unhideButton: some View {
        Button {
            showingUnhideAlert = true
        } label: {
            Image(systemName: "trash.slash")
                .padding(8)
                .background(Theme.Palette.surfaceHigh, in: Circle())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func rowView(row: ContinueViewModel.Row) -> some View {
        NavigationLink(value: row.anime) {
            HStack(spacing: 14) {
                AsyncPosterImage(url: row.anime.posterURL)
                    .frame(width: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.anime.displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                    if let ep = row.nextEpisode {
                        Text("Next: Ep \(ep.number) · \(row.progress?.translation.displayName ?? "Sub")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    if let progress = row.progress {
                        ProgressView(value: progress.fraction)
                            .tint(Theme.Palette.accent)
                        Text(progress.remainingLabel)
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.Palette.accent)
            }
            .padding(12)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
