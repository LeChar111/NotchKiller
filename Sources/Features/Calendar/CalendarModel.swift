import EventKit
import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarColor: Color

    var tint: Color { calendarColor }

    var timeLabel: String {
        guard !isAllDay else { return "Journée" }
        return "\(AgendaEvent.hour.string(from: start)) – \(AgendaEvent.hour.string(from: end))"
    }

    /// « dans 12 min », « en cours », « dans 2 h ».
    var countdown: String {
        let delta = start.timeIntervalSinceNow
        if delta < 0 { return end.timeIntervalSinceNow > 0 ? "en cours" : "passé" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "dans \(max(1, minutes)) min" }
        return "dans \(minutes / 60) h"
    }

    static let hour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()
}

@MainActor
@Observable
final class CalendarModel {
    static let shared = CalendarModel()

    private(set) var events: [AgendaEvent] = []
    private(set) var authorization: EKAuthorizationStatus = .notDetermined
    private(set) var lastAlertedID: String?

    private let store = EKEventStore()
    private var timer: Timer?

    private init() {
        authorization = EKEventStore.authorizationStatus(for: .event)
    }

    var hasAccess: Bool { authorization == .fullAccess }

    /// L'événement à annoncer dans le bandeau : celui qui commence dans moins
    /// de 30 minutes, ou celui qui est en cours.
    var imminent: AgendaEvent? {
        events.first { event in
            guard !event.isAllDay else { return false }
            let delta = event.start.timeIntervalSinceNow
            return delta < 1800 && event.end.timeIntervalSinceNow > 0
        }
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            authorization = EKEventStore.authorizationStatus(for: .event)
            refresh()
        }
    }

    func start() {
        if Demo.isActive { loadDemo(); return }
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 10

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        if Demo.isActive { loadDemo(); return }
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { events = []; return }

        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 36, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                 end: end, calendars: nil)

        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { event in
                AgendaEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Sans titre",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location?.nilIfEmpty,
                    calendarColor: event.calendar.flatMap { Color(nsColor: NSColor(cgColor: $0.cgColor) ?? .systemBlue) } ?? NK.accent
                )
            }
    }

    func markAlerted(_ id: String) { lastAlertedID = id }

    func open(_ event: AgendaEvent) {
        NSWorkspace.shared.open(URL(string: "ical://")!)
    }
}

// MARK: - Démo

extension CalendarModel {
    func loadDemo() {
        authorization = .fullAccess
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ hours: Double) -> Date { today.addingTimeInterval(hours * 3600) }
        let now = Date()
        events = [
            AgendaEvent(id: "d1", title: "Revue de design — tarifs", start: now.addingTimeInterval(18 * 60),
                        end: now.addingTimeInterval(63 * 60), isAllDay: false, location: "Salle Hopper",
                        calendarColor: .purple),
            AgendaEvent(id: "d2", title: "Point hebdo équipe produit", start: now.addingTimeInterval(3 * 3600),
                        end: now.addingTimeInterval(3.5 * 3600), isAllDay: false, location: "Visio",
                        calendarColor: .blue),
            AgendaEvent(id: "d3", title: "Sport", start: at(42.5), end: at(43.5), isAllDay: false,
                        location: nil, calendarColor: .green),
            AgendaEvent(id: "d4", title: "Sortie Lumen 2.4", start: at(24), end: at(48), isAllDay: true,
                        location: nil, calendarColor: .orange),
        ]
    }
}
