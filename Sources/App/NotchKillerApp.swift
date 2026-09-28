import SwiftUI

/// `--mcp` bascule le binaire en serveur MCP stdio : Claude Code le lance
/// comme un processus outil, sans jamais démarrer AppKit ni l'interface.
/// `--resume <pid>…` lève la pause « mémoire épuisée » ; lancé en root par l'invite admin.
@main
struct NotchKillerMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp") {
            MCPServer.run()
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--resume") {
            ProcessControl.runResumeCommand(Array(CommandLine.arguments[(flag + 1)...]))
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
