//
//  SettingsView.swift
//  LunaAnime
//
//  Settings tab. Two main sections:
//  • Providers — choose which anime scraper is active.
//  • Preferences — global defaults (dub/sub, download behaviour, etc).
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var scraperRegistry: ProviderRegistry
    @StateObject private var vm: SettingsViewModel

    init() {
        _vm = StateObject(wrappedValue: SettingsViewModel(
            registry: AppEnvironment.live.scraperRegistry,
            preferences: AppEnvironment.live.preferences
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TopBarView(title: "Settings", subtitle: "Tailor LunaAnime to your taste")

                // MARK: - Provider

                sectionHeader("Provider")
                providerSection

                // MARK: - Preferences

                sectionHeader("Preferences")
                preferencesSection

                // MARK: - About

                sectionHeader("About")
                aboutSection
            }
            .padding(.bottom, 64)
        }
        .background(Theme.Palette.background)
        .navigationBarHidden(true)
        .navigationDestination(for: SettingsRoute.self) { _ in
            ProvidersSettingsView(vm: vm)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    // MARK: - Provider section

    private var providerSection: some View {
        VStack(spacing: 8) {
            NavigationLink(value: SettingsRoute.providers) {
                HStack(spacing: 12) {
                    Image(systemName: scraperRegistry.activeProvider?.iconSystemName ?? "sparkles")
                        .font(.title3)
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anime Provider")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(scraperRegistry.activeProvider?.displayName ?? "—")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                .padding(12)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(spacing: 0) {
            settingsRow(title: "Default translation",
                         icon: "captions.bubble",
                         trailing:
                            Menu {
                                ForEach(Translation.allCases) { t in
                                    Button {
                                        vm.preferredTranslation = t
                                    } label: {
                                        Label(t.displayName,
                                              systemImage: vm.preferredTranslation == t ? "checkmark" : "")
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(vm.preferredTranslation.displayName)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.Palette.surfaceHigh, in: Capsule())
                            }
                            .foregroundStyle(Theme.Palette.textPrimary)
            )
            Divider().background(Theme.Palette.stroke)
            settingsRow(title: "Preferred quality",
                         icon: "4k.tv",
                         trailing:
                            Menu {
                                ForEach(vm.availableQualityOptions, id: \.self) { q in
                                    Button {
                                        vm.preferredQuality = q
                                    } label: {
                                        Label(q,
                                              systemImage: vm.preferredQuality == q ? "checkmark" : "")
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(vm.preferredQuality ?? "Auto")
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.Palette.surfaceHigh, in: Capsule())
                            }
                            .foregroundStyle(Theme.Palette.textPrimary)
            )
            Divider().background(Theme.Palette.stroke)
            settingsRow(title: "Download over cellular",
                        icon: "antenna.radiowaves.left.and.right",
                        trailing: Toggle("", isOn: $vm.downloadOverCellular)
                            .labelsHidden()
                            .tint(Theme.Palette.accent))
            Divider().background(Theme.Palette.stroke)
            settingsRow(title: "Auto-download next episode",
                        icon: "arrow.down.circle",
                        trailing: Toggle("", isOn: $vm.autoDownloadNextEpisode)
                            .labelsHidden()
                            .tint(Theme.Palette.accent))
            Divider().background(Theme.Palette.stroke)
            settingsRow(title: "Show NSFW content",
                        icon: "eye.slash",
                        trailing: Toggle("", isOn: $vm.showNSFWContent)
                            .labelsHidden()
                            .tint(Theme.Palette.accent))
        }
        .padding(.vertical, 4)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func settingsRow(title: String,
                             icon: String,
                             trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 32, height: 32)
                .background(Theme.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LunaAnime")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Open-source. For educational and research purposes only. You are responsible for compliance with your local laws.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack {
                Image(systemName: "chevron.left.slash.chevron.right")
                Text("github.com/yourname/lunaanime")
                    .font(.caption)
            }
            .foregroundStyle(Theme.Palette.textMuted)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
    }
}

enum SettingsRoute: Hashable {
    case providers
}
