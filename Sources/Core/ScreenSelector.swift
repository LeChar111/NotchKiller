import AppKit

@MainActor
final class ScreenSelector: ObservableObject {
    static let shared = ScreenSelector()

    @Published private(set) var availableScreens: [NSScreen] = []
    @Published private(set) var selectedScreen: NSScreen?

    private init() {
        refreshScreens()
    }

    func refreshScreens() {
        availableScreens = NSScreen.screens
        selectedScreen = NSScreen.builtInOrMain
    }

    /// Écrans qui doivent porter une encoche. L'écran intégré vient toujours
    /// en premier : c'est lui que visent le menu et les raccourcis.
    var targetScreens: [NSScreen] {
        guard AppSettings.shared.showOnAllScreens else {
            return [NSScreen.builtInOrMain]
        }
        let builtIn = NSScreen.builtInOrMain
        return [builtIn] + NSScreen.screens.filter { $0 != builtIn }
    }
}
