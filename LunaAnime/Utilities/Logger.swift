//
//  Logger.swift
//  LunaAnime
//
//  Thin wrapper around OSLog with friendly prefixes per subsystem.
//

import Foundation
import OSLog

enum LogCategory: String {
    case app, ui, network, scraper, download, player, persistence, preferences
}

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.lunaanime"

    static func debug(_ category: LogCategory, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.debug("🐛 \(message, privacy: .public)")
    }

    static func info(_ category: LogCategory, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.info("ℹ️ \(message, privacy: .public)")
    }

    static func warn(_ category: LogCategory, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.warning("⚠️ \(message, privacy: .public)")
    }

    static func error(_ category: LogCategory, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.error("🔥 \(message, privacy: .public)")
    }
}
