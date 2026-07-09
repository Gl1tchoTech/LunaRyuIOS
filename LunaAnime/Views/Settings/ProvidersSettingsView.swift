//
//  ProvidersSettingsView.swift
//  LunaAnime
//
//  Drill-down screen from Settings > Provider. Lists every AnimeProvider
//  the app ships with and lets the user make one active. Replaces the
//  "Services" tab from the old Luna-style UI.
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
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Anime Providers")
    }

    private func providerCell(_ provider: any AnimeProvider) -> some View {
        let isActive = vm.activeProviderId == provider.id
        return Button {
            vm.activeProviderId = provider.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: provider.iconSystemName)
                    .font(.title2)
                    .foregroundStyle(isActive ? .white : Theme.Palette.accent)
                    .frame(width: 48, height: 48)
                    .background(isActive ? AnyShapeStyle(Theme.Gradients.accent)
                                          : AnyShapeStyle(Theme.Palette.surfaceElevated),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    HStack(spacing: 6) {
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
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Palette.success)
                }
            }
            .padding(12)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.Palette.surfaceHigh, in: Capsule())
            .foregroundStyle(Theme.Palette.textPrimary)
    }
}
