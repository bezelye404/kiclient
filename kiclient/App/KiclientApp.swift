import SwiftUI

@main
struct KiclientApp: App {
    var body: some Scene {
        WindowGroup("kiclient") {
            MainWindowView()
                .frame(minWidth: 800, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
