import AppKit
import SwiftUI

/// Shared adaptive surfaces and type for the paired transfer workspace.
enum BenchTheme {
    static var source: Color { adaptive(light: 0xF5F3EE, dark: 0x292B2C) }
    static var remote: Color { adaptive(light: 0xF8FAFC, dark: 0x252D35) }
    static var ink: Color { adaptive(light: 0x253443, dark: 0xEDF0F2) }
    static var secondary: Color { adaptive(light: 0x64707C, dark: 0xADB7C0) }
    static var gold: Color { Color(nsColor: rgb(0xF6C845)) }
    static var divider: Color { adaptive(light: 0xD9DEE1, dark: 0x43505B) }
    static var dock: Color { adaptive(light: 0x253443, dark: 0x1C252E) }
    static var dockText: Color { Color(nsColor: rgb(0xEDF0F2)) }
    static var dockSecondary: Color { Color(nsColor: rgb(0xADB7C0)) }
    static var actionInk: Color { Color(nsColor: rgb(0x253443)) }
    static var transfer: Color { adaptive(light: 0x3689BE, dark: 0x86C6EE) }
    static let title: Font = .system(size: 25, weight: .semibold)
    static let section: Font = .system(size: 15, weight: .semibold)
    static let body: Font = .system(size: 13)
    static let metadata: Font = .system(size: 12)
    static let paneHeaderHeight: CGFloat = 136
    static let utilityHeight: CGFloat = 40
    static let footerHeight: CGFloat = 34

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
