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
        menu.addItem(NSMenuItem(title: "Configuration de la zone...", action: #selector(openConfiguration), keyEquivalent: ","))
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
    @Published var showDebugZone: Bool {
        didSet { persist(Keys.showDebugZone, showDebugZone); onChange?() }
    }

    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        zoneWidth = defaults.object(forKey: Keys.zoneWidth) as? Double ?? 300
        zoneHeight = defaults.object(forKey: Keys.zoneHeight) as? Double ?? 64
        zoneTopInset = defaults.object(forKey: Keys.zoneTopInset) as? Double ?? 0
        zoneXOffset = defaults.object(forKey: Keys.zoneXOffset) as? Double ?? 0
        widgetYOffset = defaults.object(forKey: Keys.widgetYOffset) as? Double ?? 6
        hideDelay = defaults.object(forKey: Keys.hideDelay) as? Double ?? 0.18
        showDebugZone = defaults.object(forKey: Keys.showDebugZone) as? Bool ?? false
    }

    func resetDefaults() {
        zoneWidth = 300
        zoneHeight = 64
        zoneTopInset = 0
        zoneXOffset = 0
        widgetYOffset = 6
        hideDelay = 0.18
        showDebugZone = false
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
        static let showDebugZone = "hover.zone.debug"
    }
}

final class ConfigurationWindowController {
    private let window: NSWindow

    init(settings: HoverDetectionSettings) {
        let view = ConfigurationView(settings: settings)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchKiller Configuration"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: view)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct ConfigurationView: View {
    @ObservedObject var settings: HoverDetectionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Périmètre de détection hover")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("Le widget s'affiche uniquement quand le curseur entre dans cette zone autour du notch.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            GroupBox("Zone de détection") {
                VStack(spacing: 10) {
                    SliderRow(title: "Largeur", value: $settings.zoneWidth, range: 120...900, step: 1, unit: "px")
                    SliderRow(title: "Hauteur", value: $settings.zoneHeight, range: 20...260, step: 1, unit: "px")
                    SliderRow(title: "Décalage horizontal", value: $settings.zoneXOffset, range: -420...420, step: 1, unit: "px")
                    SliderRow(title: "Départ depuis le haut", value: $settings.zoneTopInset, range: 0...220, step: 1, unit: "px")
                }
                .padding(.top, 4)
            }

            GroupBox("Comportement") {
                VStack(spacing: 10) {
                    SliderRow(title: "Position verticale widget", value: $settings.widgetYOffset, range: -40...120, step: 1, unit: "px")
                    SliderRow(title: "Délai de fermeture", value: $settings.hideDelay, range: 0.05...1.2, step: 0.01, unit: "s")
                    Toggle("Afficher la zone de détection à l'écran", isOn: $settings.showDebugZone)
                        .toggleStyle(.switch)
                }
                .padding(.top, 4)
            }

            HStack {
                Text("Zone actuelle: \(Int(settings.zoneWidth))x\(Int(settings.zoneHeight)) px")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button("Réinitialiser") {
                    settings.resetDefaults()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 470, height: 430)
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

final class NotchOverlayController {
    private let settings: HoverDetectionSettings
    private let statsModel = SystemStatsModel()
    private let window: NSWindow
    private let debugWindow = DetectionDebugWindowController()

    private var mouseTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var screenChangeObserver: Any?

    init(settings: HoverDetectionSettings) {
        self.settings = settings

        let contentSize = NSSize(width: 1160, height: 190)
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
        panel.contentView = NSHostingView(rootView: NotchWidgetView(model: statsModel))
        panel.orderOut(nil)
        window = panel

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

    private func startHoverMonitoring() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.evaluateHoverState()
        }
        timer.tolerance = 0.01
        mouseTimer = timer
    }

    private func refreshGeometry() {
        guard let screen = activeScreen() else { return }

        if settings.showDebugZone {
            debugWindow.show(frame: detectionRect(in: screen))
        } else {
            debugWindow.hide()
        }

        if window.isVisible {
            positionOverlay(on: screen)
        }
    }

    private func evaluateHoverState() {
        guard let screen = activeScreen() else { return }

        let mouse = NSEvent.mouseLocation
        let inDetectionZone = detectionRect(in: screen).contains(mouse)
        let inWidget = window.isVisible && window.frame.contains(mouse)
        let shouldShow = inDetectionZone || inWidget

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
                context.duration = 0.12
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
                context.duration = 0.12
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
        panel.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.16)
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false

        let content = NSView(frame: .zero)
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.borderWidth = 2
        content.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.85).cgColor
        content.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.15).cgColor
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

struct NotchWidgetView: View {
    @ObservedObject var model: SystemStatsModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                NookLaunchPanel()
                    .frame(width: 276)

                Divider()
                    .overlay(Color.white.opacity(0.06))
                    .padding(.vertical, 14)

                NookDatePanel(model: model)
                    .frame(width: 296)

                Divider()
                    .overlay(Color.white.opacity(0.06))
                    .padding(.vertical, 14)

                NookStatsPanel(model: model)
                    .frame(width: 330)
            }
            .frame(width: isHovered ? 936 : 900, height: isHovered ? 112 : 104)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.05, blue: 0.07),
                                Color(red: 0.01, green: 0.01, blue: 0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.black.opacity(0.98))
                    .frame(width: 166, height: 26)
                    .offset(y: -11)
            }

            NookActionRail(isHovered: isHovered)
        }
        .shadow(color: .black.opacity(0.42), radius: 25, x: 0, y: 12)
        .scaleEffect(isHovered ? 1.0 : 0.985, anchor: .top)
        .opacity(isHovered ? 1 : 0.97)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
        .compositingGroup()
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.84, blendDuration: 0.06)) {
                isHovered = hovering
            }
        }
    }
}

struct NookLaunchPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No app seems to be running")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Text("Wanna open one?")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                NookAppIcon(symbol: "music.note", tint: Color(red: 1.00, green: 0.19, blue: 0.35))
                NookAppIcon(symbol: "waveform", tint: Color(red: 0.18, green: 0.80, blue: 0.45))
                NookAppIcon(symbol: "play.fill", tint: Color(red: 1.00, green: 0.16, blue: 0.10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct NookDatePanel: View {
    @ObservedObject var model: SystemStatsModel

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd"
        return formatter
    }()

    private let weekSymbols = ["S", "S", "M", "T", "W", "T", "F"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(Self.dayFormatter.string(from: Date()))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ForEach(Array(weekSymbols.enumerated()), id: \.offset) { index, symbol in
                            Text(symbol)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(index == weekdayIndex ? Color(red: 0.21, green: 0.60, blue: 1.00) : .white.opacity(0.36))
                                .frame(width: 16)
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(index == weekdayIndex ? .white : .white.opacity(0.34))
                        }
                    }
                }
                .padding(.top, 8)
            }

            Text("Nothing for today")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var weekdayIndex: Int {
        let value = Calendar.current.component(.weekday, from: Date()) - 1
        return max(0, min(6, value))
    }
}

struct NookStatsPanel: View {
    @ObservedObject var model: SystemStatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 56)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) {
                        NookTag(text: "CPU \(model.cpuUsage)")
                        NookTag(text: "RAM \(model.memoryUsage)")
                        NookTag(text: "BAT \(model.battery)")
                    }
                    .padding(10)
                }

            HStack(spacing: 8) {
                NookMetric(icon: "arrow.down.forward", value: model.downloadSpeed)
                NookMetric(icon: "arrow.up.forward", value: model.uploadSpeed)
            }

            HStack(spacing: 10) {
                Text(model.clock)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("•")
                Text(model.networkName)
                    .lineLimit(1)
                Text("•")
                Text(model.uptime)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct NookActionRail: View {
    let isHovered: Bool
    private let symbols = ["circle.fill", "triangle.fill", "diamond.fill", "square.fill"]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Image(systemName: symbol)
                    .font(.system(size: index == 0 ? 10 : 9, weight: .semibold))
                    .foregroundStyle(index == 0 ? Color(red: 0.20, green: 0.63, blue: 1.00) : .white.opacity(0.75))
                    .frame(width: 26, height: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(index == 0 ? Color(red: 0.12, green: 0.31, blue: 0.57) : Color.white.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .frame(width: 40, height: isHovered ? 108 : 100)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.94), Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct NookAppIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: 34, height: 34)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct NookTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.38))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
    }
}

struct NookMetric: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 1.00))
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.92))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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

    var networkCompact: String {
        "\(downloadSpeed) / \(uploadSpeed)"
    }

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
            return "Aucun réseau"
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

        return "Aucun réseau"
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
