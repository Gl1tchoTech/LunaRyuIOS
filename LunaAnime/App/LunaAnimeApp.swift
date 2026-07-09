//
//  LunaAnimeApp.swift
//  LunaAnime
//
//  SwiftUI app entry point. Bootstraps the Core Data stack,
//  global preferences, and the root view.
//

import SwiftUI
import CoreData

@main
struct LunaAnimeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appEnvironment = AppEnvironment.live

    init() {
        // Configure global app-wide appearance once at startup.
        AppearanceConfigurator.configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, appEnvironment.persistence.viewContext)
                .environmentObject(appEnvironment)
                .environmentObject(appEnvironment.preferences)
                .environmentObject(appEnvironment.downloads)
                .environmentObject(appEnvironment.scraperRegistry)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Eagerly load Core Data so any migrations happen promptly.
        _ = AppEnvironment.live.persistence
        Log.info(.app, "LunaAnime launched.")
        return true
    }
}
