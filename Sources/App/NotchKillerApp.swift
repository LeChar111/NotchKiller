import SwiftUI

/// `--mcp` bascule le binaire en serveur MCP stdio : Claude Code le lance
/// comme un processus outil, sans jamais démarrer AppKit ni l'interface.
@main
struct NotchKillerMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp") {
            MCPServer.run()
        }
        NotchKillerApp.main()
    }
}

struct NotchKillerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
