import Foundation

struct OutageEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let start: Date
    var end: Date?
}

/// Persistent ring of connectivity-loss events (newest first), driven by
/// `NWPathMonitor` satisfied↔unsatisfied transitions.
@MainActor
final class ConnectivityLog: ObservableObject {
    @Published private(set) var events: [OutageEvent] = []

    private let key = "connectivityLog"
    private let limit = 200
    private let defaults = UserDefaults.standard
    private var lastSatisfied: Bool?

    init() {
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([OutageEvent].self, from: data) {
            events = stored
        }
    }

    func update(satisfied: Bool) {
        defer { lastSatisfied = satisfied }
        guard let last = lastSatisfied else {
            // Baseline after launch. If we're online, an event left open by a
            // previous session (quit/crash while offline) can never be closed
            // by a transition — cap it now. If we're offline, the persisted
            // open event correctly continues as the ongoing outage.
            if satisfied { closeOpenEvents() }
            return
        }
        guard last != satisfied else { return }

        if satisfied {
            closeOpenEvents()
        } else {
            events.insert(OutageEvent(id: UUID(), start: Date(), end: nil), at: 0)
            if events.count > limit {
                events.removeLast(events.count - limit)
            }
            save()
        }
    }

    private func closeOpenEvents() {
        var changed = false
        for index in events.indices where events[index].end == nil {
            events[index].end = Date()
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: key)
        }
    }
}
