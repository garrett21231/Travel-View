import SwiftUI

/// Named assets provide the same palette on Mac and iPhone, including dark appearance.
enum TravelTheme {
    static let background = Color("Canvas")
    static let surface = Color("Surface")
    static let ink = Color("Ink")
    static let secondary = Color("SecondaryInk")
    static let accent = Color("AccentColor")
    static let tint = Color("AccentTint")
    static let edge = Color("Edge")
}

extension View {
    func tripPanel() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TravelTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(TravelTheme.edge.opacity(0.4), lineWidth: 0.7) }
    }
}
