import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: Bandeau fermé — ce que l'utilisateur voit 99 % du temps
    var barShowCPU: Bool       { didSet { save("bar.show.cpu", barShowCPU) } }
    var barShowMusic: Bool     { didSet { save("bar.show.music", barShowMusic) } }
    var barShowClaude: Bool    { didSet { save("bar.show.claude", barShowClaude) } }
    var barShowVolumeHUD: Bool { didSet { save("bar.show.volumeHUD", barShowVolumeHUD) } }
    var barShowClaudeDone: Bool { didSet { save("bar.show.claudeDone", barShowClaudeDone) } }
    var barShowBluetooth: Bool  { didSet { save("bar.show.bluetooth", barShowBluetooth) } }
    var barShowBatteryAlerts: Bool { didSet { save("bar.show.batteryAlerts", barShowBatteryAlerts) } }
    var barShowCalendar: Bool   { didSet { save("bar.show.calendar", barShowCalendar) } }
    var replaceSystemHUD: Bool  { didSet { save("bar.replaceSystemHUD", replaceSystemHUD) } }
    var relaySystemNotifications: Bool { didSet { save("bar.relayNotifications", relaySystemNotifications) } }
    var swipeGestures: Bool     { didSet { save("panel.swipeGestures", swipeGestures) } }
    var showOnAllScreens: Bool  { didSet {
        save("panel.allScreens", showOnAllScreens)
        NotificationCenter.default.post(name: .notchScreensChanged, object: nil)
    } }
    var accentTheme: String     { didSet {
        defaults.set(accentTheme, forKey: "theme.accent")
        NK.setAccent(NKAccent(rawValue: accentTheme) ?? .bleu)
    } }

    // MARK: Panneau
    var hoverPeek: Bool        { didSet { save("panel.hoverPeek", hoverPeek) } }
    var rememberLastTab: Bool  { didSet { save("panel.rememberLastTab", rememberLastTab) } }
    var lastTab: String        { didSet { defaults.set(lastTab, forKey: "panel.lastTab") } }

    // MARK: Développement
    var defaultEditorBundleID: String { didSet { defaults.set(defaultEditorBundleID, forKey: "dev.editor") } }
    var favoriteProjects: [String]    { didSet { defaults.set(favoriteProjects, forKey: "dev.favorites") } }
    var projectRoots: [String]        { didSet { defaults.set(projectRoots, forKey: "dev.roots") } }
    var defaultMediaBundleID: String  { didSet { defaults.set(defaultMediaBundleID, forKey: "media.source") } }

    // MARK: Visibilité des statistiques (page Système)
    var showCPU: Bool     { didSet { save("stats.show.cpu", showCPU) } }
    var showRAM: Bool     { didSet { save("stats.show.ram", showRAM) } }
    var showBattery: Bool { didSet { save("stats.show.battery", showBattery) } }
    var showNetwork: Bool { didSet { save("stats.show.network", showNetwork) } }
    var showDisk: Bool    { didSet { save("stats.show.disk", showDisk) } }
    var showClock: Bool   { didSet { save("stats.show.clock", showClock) } }
    var showUptime: Bool  { didSet { save("stats.show.uptime", showUptime) } }

    private let defaults = UserDefaults.standard

    /// Les valeurs par défaut sont enregistrées dans le domaine `registration`
    /// et pas seulement dans cet initialiseur : `NotchPanelManager` lit certaines
    /// clés directement depuis `UserDefaults`, sans passer par cet objet.
    static let registeredDefaults: [String: Any] = [
        "bar.show.cpu": true,
        "bar.show.music": true,
        "bar.show.claude": true,
        "bar.show.volumeHUD": true,
        "bar.show.claudeDone": true,
        "bar.show.bluetooth": true,
        "bar.show.batteryAlerts": true,
        "bar.show.calendar": true,
        "bar.replaceSystemHUD": true,
        "bar.relayNotifications": false,
        "panel.swipeGestures": true,
        "panel.allScreens": false,
        "panel.hoverPeek": true,
        "panel.rememberLastTab": true,
        "stats.show.cpu": true,
        "stats.show.ram": true,
        "stats.show.battery": true,
        "stats.show.network": true,
        "stats.show.disk": true,
        "stats.show.clock": true,
        "stats.show.uptime": true,
    ]

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: Self.registeredDefaults)
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) as? Bool ?? fallback
        }

        barShowCPU       = bool("bar.show.cpu", true)
        barShowMusic     = bool("bar.show.music", true)
        barShowClaude    = bool("bar.show.claude", true)
        barShowVolumeHUD = bool("bar.show.volumeHUD", true)
        barShowClaudeDone = bool("bar.show.claudeDone", true)
        barShowBluetooth = bool("bar.show.bluetooth", true)
        barShowBatteryAlerts = bool("bar.show.batteryAlerts", true)
        barShowCalendar = bool("bar.show.calendar", true)
        replaceSystemHUD = bool("bar.replaceSystemHUD", true)
        relaySystemNotifications = bool("bar.relayNotifications", false)
        swipeGestures = bool("panel.swipeGestures", true)
        showOnAllScreens = bool("panel.allScreens", false)
        accentTheme = d.string(forKey: "theme.accent") ?? NKAccent.bleu.rawValue

        hoverPeek       = bool("panel.hoverPeek", true)
        rememberLastTab = bool("panel.rememberLastTab", true)
        lastTab         = d.string(forKey: "panel.lastTab") ?? "home"

        defaultEditorBundleID = d.string(forKey: "dev.editor") ?? ""
        favoriteProjects      = d.stringArray(forKey: "dev.favorites") ?? []
        projectRoots          = d.stringArray(forKey: "dev.roots") ?? ["~/Documents/Projects"]
        defaultMediaBundleID  = d.string(forKey: "media.source") ?? "com.apple.Music"

        showCPU     = bool("stats.show.cpu", true)
        showRAM     = bool("stats.show.ram", true)
        showBattery = bool("stats.show.battery", true)
        showNetwork = bool("stats.show.network", true)
        showDisk    = bool("stats.show.disk", true)
        showClock   = bool("stats.show.clock", true)
        showUptime  = bool("stats.show.uptime", true)

        NK.setAccent(NKAccent(rawValue: accentTheme) ?? .bleu)
    }

    func resetDefaults() {
        barShowCPU = true
        barShowMusic = true
        barShowClaude = true
        barShowVolumeHUD = true
        barShowClaudeDone = true
        barShowBluetooth = true
        barShowBatteryAlerts = true
        barShowCalendar = true
        replaceSystemHUD = true
        relaySystemNotifications = false
        swipeGestures = true
        showOnAllScreens = false
        accentTheme = NKAccent.bleu.rawValue
        hoverPeek = true
        rememberLastTab = true
        lastTab = "home"
        defaultEditorBundleID = ""
        favoriteProjects = []
        projectRoots = ["~/Documents/Projects"]
        defaultMediaBundleID = "com.apple.Music"
        showCPU = true
        showRAM = true
        showBattery = true
        showNetwork = true
        showDisk = true
        showClock = true
        showUptime = true
    }

    private func save(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
