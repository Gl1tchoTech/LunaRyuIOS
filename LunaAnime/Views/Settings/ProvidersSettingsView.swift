//
//  ProvidersSettingsView.swift
//  LunaAnime
//
//  Drill-down screen from Settings > Provider. Lists every AnimeProvider
//  the app ships with and lets the user make one active.
//
//  v2: catalogues (.catalogOnly) get a "Catalogue Only" pill so users know
//  they cannot playback. Providers that fail the startup ping show an
//  "Unavailable" badge and dim the cell so dead URLs don't pretend to work.
//
//

import SwiftUI

struct ProvidersSettingsView: View {

    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick the anime provider LunaAnime routes all searches, episode lists, and stream resolutions through.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(Array(AppEnvironment.live.scraperRegistry.providers.enumerated()), id: \.offset) { _, provider in
                    providerCell(provider)
                }

                Text("Catalogue providers return rich metadata (titles, posters, scores) but no playable streams — playback requires AnimePahe or another stream-capable provider added in a future release.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Anime Providers")
    }

    private func providerCell(_ provider: any AnimeProvider) -> some View {
        let isActive = vm.activeProviderId == provider.id
        let isUnavailable = AppEnvironment.live.scraperRegistry.unavailable.contains(provider.id)
        return Button {
            vm.activeProviderId = provider.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: provider.iconSystemName)
                    .font(.title2)
                    .foregroundStyle(isActive
                                      ? .white
                                      : (isUnavailable
                                         ? Theme.Palette.textMuted
                                         : Theme.Palette.accent))
                    .frame(width: 48, height: 48)
                    .background(isActive
                                ? AnyShapeStyle(Theme.Gradients.accent)
                                : AnyShapeStyle(Theme.Palette.surfaceElevated),
                                in: RoundedRectangle(cornerRadius: 12))
                    .opacity(isUnavailable && !isActive ? 0.55 : 1.0)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isUnavailable
                                             ? Theme.Palette.textSecondary
                                             : Theme.Palette.textPrimary)
                        if isUnavailable {
                            pill("Unavailable", tint: Theme.Palette.danger)
                        }
                    }
                    HStack(spacing: 6) {
                        if isUnavailable {
                            pill("Currently unreachable",
                                 tint: Theme.Palette.warning)
                        } else {
                            pillRow(for: provider)
                        }
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Palette.success)
                }
            }
            .padding(12)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func pillRow(for provider: any AnimeProvider) -> some View {
        if provider.capabilities.isCatalogOnly {
            pill("Catalogue Only", tint: Theme.Palette.accentSecondary)
        } else {
            if provider.capabilities.contains(.subTranslation) {
                pill("Sub")
            }
            if provider.capabilities.contains(.dubTranslation) {
                pill("Dub")
            }
            if provider.capabilities.contains(.directDownload) {
                pill("Direct download")
            }
        }
    }

    private func pill(_ text: String, tint: Color? = nil) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.Palette.surfaceHigh, in: Capsule())
            .foregroundStyle(tint ?? Theme.Palette.textPrimary)
    }
}
