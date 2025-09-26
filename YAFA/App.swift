import AppIntents
import SwiftUI

@main
struct YAFAApp: App {
    #if targetEnvironment(simulator)
        var sharedModelContainer = previewModelContainer()
    #else
        var sharedModelContainer = appModelContainer()
    #endif

    @State var navigationModel: NavigationModel = .init()

    init() {
        let modelContainer = self.sharedModelContainer
        let navigationModel = self.navigationModel

        AppDependencyManager.shared.add(dependency: navigationModel)
        AppDependencyManager.shared.add(dependency: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView(navigationModel: navigationModel)
        }
        .modelContainer(sharedModelContainer)
    }
}

#if DEBUG
    let developmentMode = true
#else
    let developmentMode = false
#endif
