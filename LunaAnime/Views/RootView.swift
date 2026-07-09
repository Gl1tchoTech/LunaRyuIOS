//
//  RootView.swift
//  LunaAnime
//
//  Top-level tab bar. Four tabs in the user's requested order:
//  Home, Continue, Library, Settings.
//

import SwiftUI

struct RootView: View {

    init() {}

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { ContinueView() }
                .tabItem { Label("Continue", systemImage: "play.circle.fill") }

            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .background(Theme.Palette.background)
        .toolbarBackground(Theme.Palette.background, for: .tabBar)
    }
}
