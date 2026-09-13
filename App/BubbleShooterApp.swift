import SwiftUI

@main
struct BubbleShooterApp: App {
    init() {
        Fonts.register
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
