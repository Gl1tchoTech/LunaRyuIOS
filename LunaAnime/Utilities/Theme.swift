//
//  Theme.swift
//  LunaAnime
//
//  Centralized design tokens. The palette is dark with a vibrant
//  magenta/violet accent — chosen to echo the Luna streaming app aesthetic
//  while staying distinct (no purple-pink gradient cliché).
//

import SwiftUI

enum Theme {
    // MARK: - Palette
    enum Palette {
        static let background          = Color(red: 0.06, green: 0.06, blue: 0.08)
        static let surface             = Color(red: 0.10, green: 0.10, blue: 0.12)
        static let surfaceElevated     = Color(red: 0.14, green: 0.14, blue: 0.17)
        static let surfaceHigh         = Color(red: 0.18, green: 0.18, blue: 0.22)
        static let stroke              = Color.white.opacity(0.08)
        static let strokeStrong        = Color.white.opacity(0.16)

        static let textPrimary         = Color.white
        static let textSecondary       = Color(white: 0.72)
        static let textTertiary        = Color(white: 0.52)
        static let textMuted           = Color(white: 0.38)

        static let accent              = Color(red: 0.93, green: 0.27, blue: 0.55) // pink-magenta
        static let accentSecondary     = Color(red: 0.55, green: 0.34, blue: 0.96) // violet
        static let success             = Color(red: 0.20, green: 0.84, blue: 0.55)
        static let warning             = Color(red: 1.00, green: 0.74, blue: 0.20)
        static let danger              = Color(red: 0.98, green: 0.36, blue: 0.40)
    }

    // MARK: - Gradients
    enum Gradients {
        static let heroOverlay = LinearGradient(
            colors: [
                .clear,
                Palette.background.opacity(0.45),
                Palette.background.opacity(0.92),
                Palette.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        static let accent = LinearGradient(
            colors: [Palette.accent, Palette.accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let cardShine = LinearGradient(
            colors: [Color.white.opacity(0.10), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Layout
    enum Layout {
        static let cardCorner: CGFloat      = 14
        static let posterAspect: CGFloat   = 3.0 / 4.0
        static let backdropAspect: CGFloat = 16.0 / 9.0

        static let posterWidth: CGFloat    = 130
        static let posterHeight: CGFloat   = posterWidth * posterAspect

        static let rowPosterWidth: CGFloat = 115
        static let rowPosterHeight: CGFloat = rowPosterWidth * posterAspect
    }

    // MARK: - Motion
    enum Motion {
        static let springBouncy: Animation = .spring(response: 0.45, dampingFraction: 0.72)
        static let springSnappy: Animation = .spring(response: 0.32, dampingFraction: 0.85)
        static let easeStandard: Animation = .easeInOut(duration: 0.22)
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var corner: CGFloat = Theme.Layout.cardCorner
    func body(content: Content) -> some View {
        content
            .background(Theme.Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.Palette.stroke, lineWidth: 0.7)
            )
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Group {
                    if filled {
                        Theme.Gradients.accent
                    } else {
                        Theme.Palette.surfaceHigh
                    }
                }
            )
            .foregroundColor(filled ? .white : Theme.Palette.textPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Theme.Palette.stroke, lineWidth: filled ? 0 : 0.7)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.Motion.springSnappy, value: configuration.isPressed)
    }
}

extension View {
    func card(corner: CGFloat = Theme.Layout.cardCorner) -> some View {
        modifier(CardStyle(corner: corner))
    }
}
