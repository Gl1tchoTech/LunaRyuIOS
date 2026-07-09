//
//  PlayerView.swift
//  LunaAnime
//
//  SwiftUI video player with sub/dub switching, progress persistence
//  and fullscreen controls. Wraps AVPlayerViewController for the
//  richest playback UX (PiP, AirPlay, native scrubbing).
//

import SwiftUI
import AVKit
import CoreData

struct PlayerView: View {

    let anime: AnimeSummary
    let initialEpisode: Episode
    let initialTranslation: Translation

    @EnvironmentObject private var scraperRegistry: ProviderRegistry
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Palette.background
            content
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let vm = currentVM {
            PlayerSurface(vm: vm, dismiss: { dismiss() })
                .id(vm.episode.id)   // re-create player on episode change
        } else {
            LoadingView(message: "Loading…")
        }
    }

    @State private var currentVM: PlayerViewModel?

    private func setUp() {
        if currentVM != nil { return }
        currentVM = PlayerViewModel(
            episode: initialEpisode,
            translation: initialTranslation,
            anime: anime
        )
    }
}

private struct PlayerSurface: View {

    @ObservedObject var vm: PlayerViewModel
    let dismiss: () -> Void

    @EnvironmentObject private var scraperRegistry: ProviderRegistry
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.managedObjectContext) private var moc

    var body: some View {
        ZStack {
            playerLayer
            overlayChrome
        }
        .task {
            await vm.bootstrap(downloads: downloads, registry: scraperRegistry)
        }
        .onDisappear { vm.persistProgress(moc: moc) }
        .alert("Stream error",
               isPresented: $vm.showingError,
               presenting: vm.errorMessage) { _ in
            Button("OK", role: .cancel) { dismiss() }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Player layer

    @ViewBuilder
    private var playerLayer: some View {
        if let url = vm.activeStreamURL {
            AVPlayerControllerRepresentable(player: vm.player)
                .onAppear { vm.play(url: url) }
        } else if vm.isResolving {
            LoadingView(message: "Resolving stream…")
        } else {
            EmptyStateView(systemImage: "wifi.slash",
                           title: "No playable stream",
                           message: vm.errorMessage ?? "Try a different provider or quality.")
        }
    }

    @ViewBuilder
    private var overlayChrome: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .padding(24)
        .opacity(vm.showChrome ? 1 : 0)
        .animation(Theme.Motion.easeStandard, value: vm.showChrome)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
        )
        .onTapGesture { vm.toggleChrome() }
    }

    private var topBar: some View {
        HStack {
            Button(action: dismiss) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.anime.displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Episode \(vm.episode.number) · \(vm.translation.displayName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            translationMenu
        }
    }

    private var translationMenu: some View {
        Menu {
            ForEach([Translation.sub, .dub], id: \.self) { t in
                Button {
                    Task { await vm.changeTranslation(to: t, registry: scraperRegistry) }
                } label: {
                    Label(t.displayName, systemImage: vm.translation == t ? "checkmark" : "")
                }
            }
        } label: {
            Label(vm.translation.shortLabel, systemImage: "captions.bubble")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .foregroundStyle(.white)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            Button {
                Task { await vm.previousEpisode(registry: scraperRegistry) }
            } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!vm.hasPrevious)

            Spacer()

            if vm.isBuffering {
                ProgressView().tint(.white)
            } else {
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                }
            }

            Spacer()

            Button {
                Task { await vm.nextEpisode(registry: scraperRegistry) }
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!vm.hasNext)
        }
        .font(.title2)
        .foregroundStyle(.white)
    }
}

// MARK: - AVPlayerController host

struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect
        vc.entersFullScreenWhenPlaybackBegins = false
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

// MARK: - Initialise VM helper

extension PlayerView {
    func setUpIfNeeded() {
        if currentVM == nil {
            currentVM = PlayerViewModel(
                episode: initialEpisode,
                translation: initialTranslation,
                anime: anime
            )
        }
    }
}
