import SwiftUI

/// The app's palette, copied here because the extension is a separate module
/// and must not depend on the app's views.
enum PollTheme {
    static let background = Color(hex: 0xF8F6F0)
    static let ink = Color(hex: 0x263C31)
    static let accent = Color(hex: 0xCD532D)
    static let muted = Color(hex: 0x747C72)
    static let line = Color(hex: 0xE5E5DA)
    static let green = Color(hex: 0x536D4E)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
