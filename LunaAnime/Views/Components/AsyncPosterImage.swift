//
//  AsyncPosterImage.swift
//  LunaAnime
//
//  Reusable async poster view with placeholder, cache and blur-up.
//

import SwiftUI

struct AsyncPosterImage: View {
    let url: URL?
    var aspect: CGFloat = Theme.Layout.posterAspect
    var fill: Bool = true

    var body: some View {
        ZStack {
            placeholder
            if let url = url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut(duration: 0.25))) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: fill ? .fill : .fit)
                            .clipped()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            }
        }
        .aspectRatio(1.0 / aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCorner, style: .continuous))
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [
                Theme.Palette.surfaceHigh,
                Theme.Palette.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Palette.textMuted)
        )
    }
}
