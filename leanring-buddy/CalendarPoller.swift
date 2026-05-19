//
//  CalendarPoller.swift
//  leanring-buddy
//
//  Polls Google Calendar every 60 seconds and fires a pre-call brief
//  for any event starting within the next 5 minutes.
//
//  Deduplication: each event ID is only triggered once per app session.
//

import Combine
import Foundation

@MainActor
final class CalendarPoller {

    static let shared = CalendarPoller()

    private var timer: Timer?
    private var triggeredEventIDs: Set<String> = []
    private var isRunning = false

    var onUpcomingEvent: ((CalendarEvent) -> Void)?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard !YavenUserContext.shared.entityId.isEmpty else {
            print("CalendarPoller: no entityId, skipping start")
            return
        }
        isRunning = true
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.poll() }
        }
        print("CalendarPoller: started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // MARK: - Poll

    private func poll() {
        let entityId = YavenUserContext.shared.entityId
        guard !entityId.isEmpty else { return }

        Task {
            let client = GoogleCalendarClient(entityId: entityId)
            let now = Date()
            let lookAhead = now.addingTimeInterval(5 * 60)  // 5 minutes
            let windowEnd = now.addingTimeInterval(4 * 60 * 60) // 4-hour fetch window

            guard let events = try? await client.listEvents(from: now, to: windowEnd) else { return }

            for event in events {
                guard !triggeredEventIDs.contains(event.id) else { continue }
                guard !event.attendeeEmails.isEmpty else { continue }
                guard event.startDate <= lookAhead else { continue }

                triggeredEventIDs.insert(event.id)
                print("CalendarPoller: upcoming event '\(event.title)' in \(Int(event.startDate.timeIntervalSinceNow / 60))m")
                onUpcomingEvent?(event)
            }
        }
    }
}
