import SwiftUI

@main
struct ScanToQuoteApp: App {
    @State private var store = RoomStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
