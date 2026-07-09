//
//  Extensions.swift
//  LunaAnime
//
//  Tiny reusable extensions.
//

import Foundation
import SwiftUI

extension String {
    /// Returns a slug suitable for use as a folder name.
    var folderSafe: String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let filtered = self.unicodeScalars.filter { allowed.contains($0) }
        let collapsed = String(String.UnicodeScalarView(filtered))
            .replacingOccurrences(of: " ", with: "_")
        return collapsed.isEmpty ? "untitled" : collapsed
    }

    /// Returns nil if the string is empty, otherwise self.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Int {
    /// Pads the integer to a 2-digit string ("1" -> "01", "12" -> "12").
    var padded2: String { String(format: "%02d", self) }
}

extension Double {
    /// Formats a number of bytes as a human-readable string ("1.4 GB").
    var byteSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(self))
    }
}

extension Date {
    /// "2 hours ago"-style short relative time.
    func shortRelative() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

extension View {
    /// Conditionally apply a modifier.
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

extension Color {
    /// Initialize from a hex string like "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int & 0xFF0000) >> 16) / 255
            g = Double((int & 0x00FF00) >> 8) / 255
            b = Double(int & 0x0000FF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
