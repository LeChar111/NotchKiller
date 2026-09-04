import SwiftUI
import AppKit
import IOKit.ps
import Darwin.Mach
import Darwin

@main
struct NotchKillerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = HoverDetectionSettings()
    private var overlayController: NotchOverlayController?
    private var configurationController: ConfigurationWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = NotchOverlayController(settings: settings)
        configurationController = ConfigurationWindowController(settings: settings)

        setupStatusItem()
    }

    @objc private func openWidget() {
        overlayController?.showFromMenu()
    }

    @objc private func openConfiguration() {
        configurationController?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.portrait.tophalf.filled", accessibilityDescription: "NotchKiller")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Afficher le widget", action: #selector(openWidget), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Configuration...", action: #selector(openConfiguration), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quitter NotchKiller", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }
}

final class HoverDetectionSettings: ObservableObject {
    @Published var zoneWidth: Double {
        didSet { persist(Keys.zoneWidth, zoneWidth); onChange?() }
    }
    @Published var zoneHeight: Double {
        didSet { persist(Keys.zoneHeight, zoneHeight); onChange?() }
    }
    @Published var zoneTopInset: Double {
        didSet { persist(Keys.zoneTopInset, zoneTopInset); onChange?() }
    }
    @Published var zoneXOffset: Double {
        didSet { persist(Keys.zoneXOffset, zoneXOffset); onChange?() }
    }
    @Published var widgetYOffset: Double {
        didSet { persist(Keys.widgetYOffset, widgetYOffset); onChange?() }
    }
    @Published var hideDelay: Double {
        didSet { persist(Keys.hideDelay, hideDelay); onChange?() }
    }
    @Published var panelWidth: Double {
        didSet { persist(Keys.panelWidth, panelWidth); onChange?() }
    }
    @Published var panelHeight: Double {
        didSet { persist(Keys.panelHeight, panelHeight); onChange?() }
    }
    @Published var showDebugZone: Bool {
        didSet { persist(Keys.showDebugZone, showDebugZone); onChange?() }
    }

    @Published var showCPU: Bool {
        didSet { persist(Keys.showCPU, showCPU); onChange?() }
    }
    @Published var showRAM: Bool {
        didSet { persist(Keys.showRAM, showRAM); onChange?() }
    }
    @Published var showBattery: Bool {
        didSet { persist(Keys.showBattery, showBattery); onChange?() }
    }
    @Published var showNetwork: Bool {
        didSet { persist(Keys.showNetwork, showNetwork); onChange?() }
    }
    @Published var showDisk: Bool {
        didSet { persist(Keys.showDisk, showDisk); onChange?() }
    }
    @Published var showClock: Bool {
        didSet { persist(Keys.showClock, showClock); onChange?() }
    }
    @Published var showUptime: Bool {
        didSet { persist(Keys.showUptime, showUptime); onChange?() }
    }

    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        zoneWidth = defaults.object(forKey: Keys.zoneWidth) as? Double ?? 360
        zoneHeight = defaults.object(forKey: Keys.zoneHeight) as? Double ?? 82
        zoneTopInset = defaults.object(forKey: Keys.zoneTopInset) as? Double ?? 0
        zoneXOffset = defaults.object(forKey: Keys.zoneXOffset) as? Double ?? 0
        widgetYOffset = defaults.object(forKey: Keys.widgetYOffset) as? Double ?? -8
        hideDelay = defaults.object(forKey: Keys.hideDelay) as? Double ?? 0.22
        panelWidth = defaults.object(forKey: Keys.panelWidth) as? Double ?? 1120
        panelHeight = defaults.object(forKey: Keys.panelHeight) as? Double ?? 186
        showDebugZone = defaults.object(forKey: Keys.showDebugZone) as? Bool ?? false

        showCPU = defaults.object(forKey: Keys.showCPU) as? Bool ?? true
        showRAM = defaults.object(forKey: Keys.showRAM) as? Bool ?? true
        showBattery = defaults.object(forKey: Keys.showBattery) as? Bool ?? true
        showNetwork = defaults.object(forKey: Keys.showNetwork) as? Bool ?? true
        showDisk = defaults.object(forKey: Keys.showDisk) as? Bool ?? true
        showClock = defaults.object(forKey: Keys.showClock) as? Bool ?? true
        showUptime = defaults.object(forKey: Keys.showUptime) as? Bool ?? true
    }

    func resetDefaults() {
        zoneWidth = 360
        zoneHeight = 82
        zoneTopInset = 0
        zoneXOffset = 0
        widgetYOffset = -8
        hideDelay = 0.22
        panelWidth = 1120
        panelHeight = 186
        showDebugZone = false

        showCPU = true
        showRAM = true
        showBattery = true
        showNetwork = true
        showDisk = true
        showClock = true
        showUptime = true
    }

    private func persist(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persist(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private enum Keys {
        static let zoneWidth = "hover.zone.width"
        static let zoneHeight = "hover.zone.height"
        static let zoneTopInset = "hover.zone.topInset"
        static let zoneXOffset = "hover.zone.xOffset"
        static let widgetYOffset = "widget.yOffset"
        static let hideDelay = "hover.hide.delay"
        static let panelWidth = "panel.width"
        static let panelHeight = "panel.height"
        static let showDebugZone = "hover.zone.debug"

        static let showCPU = "stats.show.cpu"
        static let showRAM = "stats.show.ram"
        static let showBattery = "stats.show.battery"
        static let showNetwork = "stats.show.network"
        static let showDisk = "stats.show.disk"
        static let showClock = "stats.show.clock"
        static let showUptime = "stats.show.uptime"
    }
}

final class ConfigurationWindowController {
    private let window: NSWindow

    init(settings: HoverDetectionSettings) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 670),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchKiller Configuration"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 620)
        window.center()
        window.contentView = NSHostingView(
            rootView: ScrollView {
                SettingsPanelView(settings: settings, compact: false)
                    .padding(16)
            }
            .frame(minWidth: 500, minHeight: 620)
        )
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

final class NotchOverlayController {
    private let settings: HoverDetectionSettings
    private let statsModel = SystemStatsModel()
    private let window: NSWindow
    private let debugWindow = DetectionDebugWindowController()

    private var mouseTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var screenChangeObserver: Any?
    private var manualPinnedUntil: Date?

    init(settings: HoverDetectionSettings) {
        self.settings = settings

        let contentSize = NSSize(width: settings.panelWidth + 120, height: settings.panelHeight + 36)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.orderOut(nil)
        window = panel
        panel.contentView = NSHostingView(rootView: NotchWidgetView(model: statsModel, settings: settings, pinOverlay: { [weak self] in
            self?.pinInteraction(seconds: 8)
        }))

        settings.onChange = { [weak self] in
            self?.refreshGeometry()
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshGeometry()
        }

        refreshGeometry()
        startHoverMonitoring()
    }

    deinit {
        mouseTimer?.invalidate()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func showFromMenu() {
        pinInteraction(seconds: 10)
        if let screen = activeScreen() {
            showOverlay(on: screen)
        }
    }

    private func pinInteraction(seconds: TimeInterval) {
        manualPinnedUntil = Date().addingTimeInterval(seconds)
    }

    private func startHoverMonitoring() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
            self?.evaluateHoverState()
        }
        timer.tolerance = 0.01
        mouseTimer = timer
    }

    private func refreshGeometry() {
        guard let screen = activeScreen() else { return }

        updateWindowSize()

        if settings.showDebugZone {
            debugWindow.show(frame: detectionRect(in: screen))
        } else {
            debugWindow.hide()
        }

        if window.isVisible {
            positionOverlay(on: screen)
        }
    }

    private func updateWindowSize() {
        let contentWidth = max(980, settings.panelWidth + 120)
        let contentHeight = max(180, settings.panelHeight + 36)
        let newSize = NSSize(width: contentWidth, height: contentHeight)

        if window.contentView?.frame.size != newSize {
            window.setContentSize(newSize)
        }
    }

    private func evaluateHoverState() {
        guard let screen = activeScreen() else { return }

        let mouse = NSEvent.mouseLocation
        let inDetectionZone = detectionRect(in: screen).contains(mouse)
        let inWidget = window.isVisible && window.frame.contains(mouse)
        let now = Date()
        let isPinned = (manualPinnedUntil != nil) && (manualPinnedUntil ?? now) > now
        if !isPinned {
            manualPinnedUntil = nil
        }
        let shouldShow = inDetectionZone || inWidget || isPinned

        if settings.showDebugZone {
            debugWindow.show(frame: detectionRect(in: screen))
        } else {
            debugWindow.hide()
        }

        if shouldShow {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            showOverlay(on: screen)
        } else {
            scheduleHide()
        }
    }

    private func showOverlay(on screen: NSScreen) {
        positionOverlay(on: screen)
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                window.animator().alphaValue = 1
            }
        }
    }

    private func scheduleHide() {
        guard window.isVisible else { return }
        guard hideWorkItem == nil else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                self.window.animator().alphaValue = 0
            } completionHandler: {
                self.window.orderOut(nil)
                self.window.alphaValue = 1
            }
            self.hideWorkItem = nil
        }

        hideWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hideDelay, execute: task)
    }

    private func positionOverlay(on screen: NSScreen) {
        let frame = screen.frame
        let size = window.frame.size
        let x = frame.midX - (size.width / 2)
        let y = frame.maxY - size.height + CGFloat(settings.widgetYOffset)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func detectionRect(in screen: NSScreen) -> NSRect {
        let width = CGFloat(settings.zoneWidth)
        let height = CGFloat(settings.zoneHeight)
        let x = screen.frame.midX - (width / 2) + CGFloat(settings.zoneXOffset)
        let y = screen.frame.maxY - CGFloat(settings.zoneTopInset) - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

final class DetectionDebugWindowController {
    private let window: NSWindow

    init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false

        let content = NSView(frame: .zero)
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 2
        content.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        content.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
        panel.contentView = content

        panel.orderOut(nil)
        window = panel
    }

    func show(frame: NSRect) {
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        if window.isVisible {
            window.orderOut(nil)
        }
    }
}

enum WidgetPage: String, CaseIterable {
    case home = "Accueil"
    case stats = "Stats"
    case tools = "Outils"
    case settings = "Param"

    var symbol: String {
        switch self {
        case .home: return "circle.fill"
        case .stats: return "triangle.fill"
        case .tools: return "square.fill"
        case .settings: return "diamond.fill"
        }
    }
}

struct NotchWidgetView: View {
    @ObservedObject var model: SystemStatsModel
    @ObservedObject var settings: HoverDetectionSettings
    let pinOverlay: () -> Void

    @State private var activePage: WidgetPage = .home
    @State private var isHovered = false
    @State private var noteText = ""
    @State private var formatUppercase = false
    @State private var formatBold = false
    @State private var formatItalic = false
    @State private var formatUnderline = false
    @State private var toolMessage = "Ready"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            mainShell
            NookActionRail(activePage: $activePage) {
                pinOverlay()
            }
            .frame(height: settings.panelHeight - 6, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 1)
        .scaleEffect(isHovered ? 1.0 : 0.99, anchor: .top)
        .onHover { hovering in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84, blendDuration: 0.08)) {
                isHovered = hovering
            }
        }
    }

    private var mainShell: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 36,
                    bottomLeading: 44,
                    bottomTrailing: 44,
                    topTrailing: 36
                ),
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.03, blue: 0.05),
                        Color(red: 0.00, green: 0.00, blue: 0.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 36,
                        bottomLeading: 44,
                        bottomTrailing: 44,
                        topTrailing: 36
                    ),
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)

            Capsule()
                .fill(Color.black.opacity(0.99))
                .frame(width: 220, height: 36)
                .offset(y: -18)

            VStack(spacing: 0) {
                TopMiniBar()
                    .padding(.top, 6)

                pageContent
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: settings.panelWidth, height: settings.panelHeight)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch activePage {
        case .home:
            HomePageView(
                model: model,
                settings: settings,
                noteText: $noteText,
                formatUppercase: $formatUppercase,
                formatBold: $formatBold,
                formatItalic: $formatItalic,
                formatUnderline: $formatUnderline,
                launchMusic: {
                    pinOverlay()
                    _ = ActionLauncher.openMusic()
                },
                launchSpotify: {
                    pinOverlay()
                    _ = ActionLauncher.openSpotify()
                },
                launchYouTube: {
                    pinOverlay()
                    _ = ActionLauncher.openYouTube()
                }
            )
        case .stats:
            StatsPageView(model: model, settings: settings)
        case .tools:
            ToolsPageView(settings: settings, message: $toolMessage) { action in
                pinOverlay()
                runToolAction(action)
            }
        case .settings:
            ScrollView(showsIndicators: false) {
                SettingsPanelView(settings: settings, compact: true)
                    .padding(.top, 2)
            }
        }
    }

    private func runToolAction(_ action: ToolAction) {
        switch action {
        case .openFinder:
            toolMessage = ActionLauncher.openFinder() ? "Finder opened" : "Failed to open Finder"
        case .openActivity:
            toolMessage = ActionLauncher.openActivityMonitor() ? "Activity Monitor opened" : "Failed to open Activity Monitor"
        case .openConsole:
            toolMessage = ActionLauncher.openConsole() ? "Console opened" : "Failed to open Console"
        case .lockScreen:
            toolMessage = ActionLauncher.lockScreen() ? "Screen locked" : "Failed to lock screen"
        case .toggleDebugZone:
            settings.showDebugZone.toggle()
            toolMessage = settings.showDebugZone ? "Hover zone debug ON" : "Hover zone debug OFF"
        case .openSystemSettings:
            toolMessage = ActionLauncher.openSystemSettings() ? "System Settings opened" : "Failed to open System Settings"
        }
    }
}

struct TopMiniBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 170, height: 52)
                .overlay {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                        Text("Nook")
                            .font(.system(size: 39 / 2, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.95))
                }

            Capsule()
                .fill(Color.white.opacity(0.03))
                .frame(width: 150, height: 52)
                .overlay {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Tray")
                            .font(.system(size: 39 / 2, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.44))
                }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
    }
}

struct HomePageView: View {
    @ObservedObject var model: SystemStatsModel
    @ObservedObject var settings: HoverDetectionSettings
    @Binding var noteText: String
    @Binding var formatUppercase: Bool
    @Binding var formatBold: Bool
    @Binding var formatItalic: Bool
    @Binding var formatUnderline: Bool
    let launchMusic: () -> Void
    let launchSpotify: () -> Void
    let launchYouTube: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VerticalSeparator()

            centerPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VerticalSeparator()

            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 122)
        .onChange(of: formatUppercase) { upper in
            if upper {
                noteText = noteText.uppercased()
            }
        }
    }

    private var leftPanel: some View {
        VStack(alignment: .center, spacing: 9) {
            Text("No app seems to be running")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Text("Wanna open one?")
                .font(.system(size: 57 / 2, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                AppLaunchButton(symbol: "music.note", tint: Color(red: 0.98, green: 0.16, blue: 0.42), action: launchMusic)
                AppLaunchButton(symbol: "waveform", tint: Color(red: 0.14, green: 0.78, blue: 0.43), action: launchSpotify)
                AppLaunchButton(symbol: "play.fill", tint: Color(red: 0.98, green: 0.11, blue: 0.06), action: launchYouTube)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var centerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(Self.monthFormatter.string(from: Date()))
                    .font(.system(size: 72 / 2, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 9) {
                        ForEach(Array(Self.weekHeaders.enumerated()), id: \.offset) { idx, item in
                            Text(item)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(idx == weekdayIndex ? Color(red: 0.07, green: 0.62, blue: 1.00) : .white.opacity(0.22))
                        }
                    }

                    HStack(spacing: 9) {
                        ForEach(1..<8, id: \.self) { number in
                            Text(String(format: "%02d", number))
                                .font(.system(size: number == dayHighlight ? 50 / 2 : 33 / 2, weight: .bold, design: .monospaced))
                                .foregroundStyle(number == dayHighlight ? Color(red: 0.08, green: 0.62, blue: 1.00) : .white.opacity(0.34))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                Text("Nothing for today")
            }
            .font(.system(size: 52 / 2, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .overlay {
                    ZStack(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text("Take a quick note...")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.26))
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                        }

                        TextEditor(text: editorBinding)
                            .font(.system(size: 15, weight: formatBold ? .bold : .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .modifier(ItalicAndUnderline(italic: formatItalic, underline: formatUnderline))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Button {
                        noteText = ""
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0.10, green: 0.58, blue: 1.00))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .padding(.bottom, 10)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 8) {
                        FormatToolButton(label: "{}", active: false) {
                            noteText.append("{}")
                        }
                        FormatToolButton(label: "A", active: formatUppercase) {
                            formatUppercase.toggle()
                        }
                        FormatToolButton(label: "B", active: formatBold) {
                            formatBold.toggle()
                        }
                        FormatToolButton(label: "I", active: formatItalic) {
                            formatItalic.toggle()
                        }
                        FormatToolButton(label: "U", active: formatUnderline) {
                            formatUnderline.toggle()
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var weekdayIndex: Int {
        let day = Calendar.current.component(.weekday, from: Date()) - 1
        return max(0, min(6, day))
    }

    private var dayHighlight: Int {
        let day = Calendar.current.component(.day, from: Date())
        let result = day % 7
        return result == 0 ? 7 : result
    }

    private var editorBinding: Binding<String> {
        Binding(
            get: { noteText },
            set: { newValue in
                noteText = formatUppercase ? newValue.uppercased() : newValue
            }
        )
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let weekHeaders = ["S", "S", "M", "T", "W", "T", "F"]
}

struct StatsPageView: View {
    @ObservedObject var model: SystemStatsModel
    @ObservedObject var settings: HoverDetectionSettings

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cards) { card in
                    StatCard(title: card.title, value: card.value, icon: card.icon, progress: card.progress)
                }
            }
        }
    }

    private var cards: [StatCardData] {
        var result: [StatCardData] = []
        if settings.showCPU {
            result.append(.init(title: "CPU", value: model.cpuUsage, icon: "cpu", progress: percentFromString(model.cpuUsage)))
        }
        if settings.showRAM {
            result.append(.init(title: "RAM", value: model.memoryUsage, icon: "memorychip", progress: percentFromString(model.memoryUsage)))
        }
        if settings.showBattery {
            result.append(.init(title: "Battery", value: model.battery, icon: "battery.100", progress: percentFromString(model.battery)))
        }
        if settings.showNetwork {
            result.append(.init(title: "Download", value: model.downloadSpeed, icon: "arrow.down.forward", progress: nil))
            result.append(.init(title: "Upload", value: model.uploadSpeed, icon: "arrow.up.forward", progress: nil))
        }
        if settings.showDisk {
            result.append(.init(title: "Disk", value: model.diskUsage, icon: "internaldrive", progress: percentFromString(model.diskUsage)))
        }
        if settings.showClock {
            result.append(.init(title: "Clock", value: model.clock, icon: "clock", progress: nil))
        }
        if settings.showUptime {
            result.append(.init(title: "Uptime", value: model.uptime, icon: "timer", progress: nil))
        }
        result.append(.init(title: "Network", value: model.networkName, icon: "network", progress: nil))
        return result
    }

    private func percentFromString(_ text: String) -> Double? {
        guard let value = Double(text.filter({ "0123456789.".contains($0) })) else {
            return nil
        }
        if text.contains("%") {
            return max(0, min(1, value / 100))
        }
        return nil
    }
}

struct StatCardData: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let progress: Double?
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(Color(red: 0.16, green: 0.62, blue: 1.00))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let progress {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(red: 0.08, green: 0.58, blue: 1.00))
                                .frame(width: width * CGFloat(progress))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }
}

enum ToolAction: String, CaseIterable {
    case openFinder = "Open Finder"
    case openActivity = "Activity Monitor"
    case openConsole = "Console"
    case openSystemSettings = "System Settings"
    case lockScreen = "Lock Screen"
    case toggleDebugZone = "Toggle Debug Zone"

    var symbol: String {
        switch self {
        case .openFinder: return "folder"
        case .openActivity: return "waveform.path.ecg"
        case .openConsole: return "terminal"
        case .openSystemSettings: return "gear"
        case .lockScreen: return "lock.shield"
        case .toggleDebugZone: return "scope"
        }
    }
}

struct ToolsPageView: View {
    @ObservedObject var settings: HoverDetectionSettings
    @Binding var message: String
    let onAction: (ToolAction) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick actions")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ToolAction.allCases, id: \.self) { action in
                    Button {
                        onAction(action)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbol)
                            Text(action.rawValue)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(action == .toggleDebugZone && settings.showDebugZone ? 0.18 : 0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.10, green: 0.60, blue: 1.00))
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .padding(.top, 4)
        }
    }
}

struct SettingsPanelView: View {
    @ObservedObject var settings: HoverDetectionSettings
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            Text("Parametres widget")
                .font(.system(size: compact ? 16 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            GroupBox("Layout") {
                VStack(spacing: 10) {
                    SliderRow(title: "Largeur widget", value: $settings.panelWidth, range: 940...1400, step: 1, unit: "px")
                    SliderRow(title: "Hauteur widget", value: $settings.panelHeight, range: 150...280, step: 1, unit: "px")
                    SliderRow(title: "Position Y", value: $settings.widgetYOffset, range: -80...40, step: 1, unit: "px")
                }
                .padding(.top, 4)
            }

            GroupBox("Detection hover") {
                VStack(spacing: 10) {
                    SliderRow(title: "Zone largeur", value: $settings.zoneWidth, range: 120...900, step: 1, unit: "px")
                    SliderRow(title: "Zone hauteur", value: $settings.zoneHeight, range: 20...260, step: 1, unit: "px")
                    SliderRow(title: "Zone X", value: $settings.zoneXOffset, range: -420...420, step: 1, unit: "px")
                    SliderRow(title: "Inset top", value: $settings.zoneTopInset, range: 0...220, step: 1, unit: "px")
                    SliderRow(title: "Hide delay", value: $settings.hideDelay, range: 0.05...1.2, step: 0.01, unit: "s")
                    Toggle("Afficher la zone de detection", isOn: $settings.showDebugZone)
                        .toggleStyle(.switch)
                }
                .padding(.top, 4)
            }

            GroupBox("Statistiques affichees") {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("CPU", isOn: $settings.showCPU)
                        Toggle("RAM", isOn: $settings.showRAM)
                        Toggle("Batterie", isOn: $settings.showBattery)
                        Toggle("Reseau", isOn: $settings.showNetwork)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Disque", isOn: $settings.showDisk)
                        Toggle("Heure", isOn: $settings.showClock)
                        Toggle("Uptime", isOn: $settings.showUptime)
                    }
                }
                .toggleStyle(.switch)
                .padding(.top, 4)
            }

            HStack {
                Button("Reset defaults") {
                    settings.resetDefaults()
                }

                Spacer(minLength: 0)

                Text("\(Int(settings.panelWidth))x\(Int(settings.panelHeight))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(compact ? 0 : 2)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(formattedValue) \(unit)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }

    private var formattedValue: String {
        if step < 1 {
            return String(format: "%.2f", value)
        }
        return String(Int(value))
    }
}

struct NookActionRail: View {
    @Binding var activePage: WidgetPage
    let onPageChanged: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(WidgetPage.allCases, id: \.self) { page in
                Button {
                    activePage = page
                    onPageChanged()
                } label: {
                    Image(systemName: page.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(activePage == page ? Color(red: 0.12, green: 0.65, blue: 1.00) : .white.opacity(0.68))
                        .frame(width: 40, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(activePage == page ? Color.white.opacity(0.13) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(Color.white.opacity(activePage == page ? 0.18 : 0.08), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(page.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 60, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.95), Color.black.opacity(0.84)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }
}

struct VerticalSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1)
            .padding(.vertical, 6)
    }
}

struct AppLaunchButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint)
                .frame(width: 66, height: 58)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct FormatToolButton: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.58))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(active ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}

struct ItalicAndUnderline: ViewModifier {
    let italic: Bool
    let underline: Bool

    func body(content: Content) -> some View {
        if italic {
            content
                .italic()
                .underline(underline)
        } else {
            content
                .underline(underline)
        }
    }
}

struct NookTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

struct NookMetric: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(Color(red: 0.10, green: 0.62, blue: 1.00))
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.94))
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

enum ActionLauncher {
    static func openMusic() -> Bool {
        return openBundleID("com.apple.Music")
    }

    static func openSpotify() -> Bool {
        if openBundleID("com.spotify.client") {
            return true
        }
        return openURL("https://open.spotify.com")
    }

    static func openYouTube() -> Bool {
        return openURL("https://www.youtube.com")
    }

    static func openFinder() -> Bool {
        return openBundleID("com.apple.finder")
    }

    static func openActivityMonitor() -> Bool {
        return openBundleID("com.apple.ActivityMonitor")
    }

    static func openConsole() -> Bool {
        return openBundleID("com.apple.Console")
    }

    static func openSystemSettings() -> Bool {
        return openBundleID("com.apple.systempreferences") || openURL("x-apple.systempreferences:")
    }

    static func lockScreen() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        task.arguments = ["-suspend"]
        do {
            try task.run()
            return true
        } catch {
            return false
        }
    }

    private static func openBundleID(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return true
    }

    private static func openURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

final class SystemStatsModel: ObservableObject {
    @Published var cpuUsage: String = "--"
    @Published var memoryUsage: String = "--"
    @Published var battery: String = "N/A"
    @Published var downloadSpeed: String = "--"
    @Published var uploadSpeed: String = "--"
    @Published var diskUsage: String = "--"
    @Published var clock: String = "--:--"
    @Published var uptime: String = "--"
    @Published var networkName: String = "--"

    private var timer: Timer?
    private var previousCPUTicks = [UInt32](repeating: 0, count: Int(CPU_STATE_MAX))
    private var hasPreviousCPU = false

    private var previousRxBytes: UInt64 = 0
    private var previousTxBytes: UInt64 = 0
    private var previousNetTimestamp: TimeInterval = Date().timeIntervalSince1970

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 0.2
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        let cpu = computeCPUUsage()
        cpuUsage = String(format: "%.0f%%", cpu)

        let memory = computeMemoryUsage()
        memoryUsage = String(format: "%.0f%%", memory)

        if let batteryValue = computeBatteryStatus() {
            battery = batteryValue
        } else {
            battery = "N/A"
        }

        let (download, upload) = computeNetworkSpeed()
        downloadSpeed = formatBytesPerSecond(download)
        uploadSpeed = formatBytesPerSecond(upload)

        diskUsage = computeDiskUsage()
        clock = Self.clockFormatter.string(from: Date())
        uptime = formatUptime(ProcessInfo.processInfo.systemUptime)
        networkName = currentNetworkInterface()
    }

    private func computeCPUUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuLoadInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let ticks: [UInt32] = [
            cpuLoadInfo.cpu_ticks.0,
            cpuLoadInfo.cpu_ticks.1,
            cpuLoadInfo.cpu_ticks.2,
            cpuLoadInfo.cpu_ticks.3
        ]

        guard hasPreviousCPU else {
            previousCPUTicks = ticks
            hasPreviousCPU = true
            return 0
        }

        let diff = zip(ticks, previousCPUTicks).map { current, previous in
            current >= previous ? current - previous : current
        }

        previousCPUTicks = ticks

        let totalTicks = diff.reduce(0, +)
        guard totalTicks > 0 else { return 0 }

        let idleTicks = diff[Int(CPU_STATE_IDLE)]
        let usage = Double(totalTicks - idleTicks) / Double(totalTicks) * 100
        return max(0, min(100, usage))
    }

    private func computeMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let usedPages = stats.active_count + stats.inactive_count + stats.wire_count
        let usedBytes = Double(usedPages) * Double(vm_kernel_page_size)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

        guard totalBytes > 0 else { return 0 }
        let usage = usedBytes / totalBytes * 100
        return max(0, min(100, usage))
    }

    private func computeBatteryStatus() -> String? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = list.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
            let current = description[kIOPSCurrentCapacityKey as String] as? Int,
            let max = description[kIOPSMaxCapacityKey as String] as? Int,
            max > 0
        else {
            return nil
        }

        let percent = Int((Double(current) / Double(max)) * 100)
        let charging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
        let suffix = charging ? " (charge)" : ""
        return "\(percent)%\(suffix)"
    }

    private func computeNetworkSpeed() -> (Double, Double) {
        let now = Date().timeIntervalSince1970
        let elapsed = max(now - previousNetTimestamp, 1)
        let (rxBytes, txBytes) = networkBytes()

        defer {
            previousRxBytes = rxBytes
            previousTxBytes = txBytes
            previousNetTimestamp = now
        }

        guard previousRxBytes > 0 || previousTxBytes > 0 else {
            return (0, 0)
        }

        let down = Double(rxBytes.saturatingSubtract(previousRxBytes)) / elapsed
        let up = Double(txBytes.saturatingSubtract(previousTxBytes)) / elapsed
        return (down, up)
    }

    private func networkBytes() -> (UInt64, UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback,
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx = rx.saturatingAdd(UInt64(data.pointee.ifi_ibytes))
                tx = tx.saturatingAdd(UInt64(data.pointee.ifi_obytes))
            }

            pointer = current.pointee.ifa_next
        }

        return (rx, tx)
    }

    private func computeDiskUsage() -> String {
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
            let total = (attributes[.systemSize] as? NSNumber)?.doubleValue,
            let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue,
            total > 0
        else {
            return "--"
        }

        let used = total - free
        let usedPercent = (used / total) * 100
        let usedGB = used / 1_073_741_824
        return String(format: "%.0f%% (%.0f GB)", usedPercent, usedGB)
    }

    private func formatBytesPerSecond(_ value: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var speed = max(0, value)
        var index = 0

        while speed >= 1024 && index < units.count - 1 {
            speed /= 1024
            index += 1
        }

        if index == 0 {
            return String(format: "%.0f %@", speed, units[index])
        }

        return String(format: "%.1f %@", speed, units[index])
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        if days > 0 {
            return "\(days)j \(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    private func currentNetworkInterface() -> String {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else {
            return "Aucun reseau"
        }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback,
               let nameCString = current.pointee.ifa_name {
                let name = String(cString: nameCString)
                if !name.isEmpty {
                    return name
                }
            }

            pointer = current.pointee.ifa_next
        }

        return "Aucun reseau"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : result
    }

    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        let (result, overflow) = subtractingReportingOverflow(other)
        return overflow ? 0 : result
    }
}
