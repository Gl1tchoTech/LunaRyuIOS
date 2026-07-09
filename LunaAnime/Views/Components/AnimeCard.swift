//
//  AnimeCard.swift
//  LunaAnime
//
//  Reusable poster card used in Home, Continue and Library grids/rows.
//

import SwiftUI

struct AnimeCard: View {

    let anime: AnimeSummary
    var trailingBadge: String? = nil
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncPosterImage(url: anime.posterURL)
                if let badge = trailingBadge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
                if let progress = progress {
                    VStack {
                        Spacer()
                        ProgressView(value: progress)
                            .tint(Theme.Palette.accent)
                            .scaleEffect(y: 0.6, anchor: .bottom)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
            }
            Text(anime.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let year = anime.year {
                Text(String(year))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(width: Theme.Layout.posterWidth, alignment: .leading)
    }
}

struct AnimeRow: View {
    let anime: AnimeSummary
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            AsyncPosterImage(url: anime.posterURL)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(anime.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .padding(.vertical, 4)
    }
}
