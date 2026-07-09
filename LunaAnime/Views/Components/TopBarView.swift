//
//  TopBarView.swift
//  LunaAnime
//
//  Top bar component with optional search field.
//

import SwiftUI

struct TopBarView: View {
    let title: String
    var subtitle: String? = nil
    var searchText: Binding<String>? = nil
    var trailingButton: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                Spacer()
                if let trailingButton = trailingButton {
                    trailingButton
                }
            }
            if let searchText = searchText {
                searchField(text: searchText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField("Search anime…", text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
        }
        .padding(10)
        .background(Theme.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
    }
}
