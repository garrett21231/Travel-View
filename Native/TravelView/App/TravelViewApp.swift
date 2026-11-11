import SwiftUI

/// One shared store keeps multiple Mac windows in sync after each committed save.
@main
struct TravelViewApp: App {
    @State private var store = TripStore()

    var body: some Scene {
        WindowGroup {
            TripLibraryView(store: store)
                .tint(TravelTheme.accent)
                .frame(minWidth: 320, minHeight: 420)
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 720)
        #endif
    }
}
