//
//  LoadingView.swift
//  LunaAnime
//
//  Centered spinner with optional message.
//

import SwiftUI

struct LoadingView: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Theme.Palette.accent)
                .scaleEffect(1.4)
            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
    }
}
