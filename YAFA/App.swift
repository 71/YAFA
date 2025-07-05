import SwiftUI

@main
struct YAFAApp: App {
    #if targetEnvironment(simulator)
        var sharedModelContainer = previewModelContainer()
    #else
        var sharedModelContainer = appModelContainer()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

#if DEBUG
    let developmentMode = true
#else
    let developmentMode = false
#endif
