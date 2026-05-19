//
//  GoogleCalendarClient.swift
//  leanring-buddy
//
//  Composio client for Google Calendar — same pattern as GmailComposioClient.
//  Fetches upcoming events so CalendarPoller can detect calls starting soon.
//

import Foundation

struct CalendarEvent {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let attendeeEmails: [String]
    let meetLink: String?
}

struct GoogleCalendarClient {

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    let entityId: String

    // MARK: - Calendar Actions

    /// Returns events starting between `from` and `to`.
    func listEvents(from: Date, to: Date, maxResults: Int = 20) async throws -> [CalendarEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let data = try await execute(action: "GOOGLECALENDAR_LIST_EVENTS", input: [
            "calendar_id": "primary",
            "time_min": formatter.string(from: from),
            "time_max": formatter.string(from: to),
            "max_results": maxResults,
            "single_events": true,
            "order_by": "startTime",
        ])
        return parseEvents(from: data)
    }

    // MARK: - Core HTTP

    private func execute(action: String, input: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(workerBaseURL)/execute") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "actionSlug": action,
            "entityId": entityId,
            "arguments": input,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            let detail = String(data: data, encoding: .utf8) ?? "no detail"
            throw NSError(domain: "GoogleCalendar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(action) failed: \(detail)"
            ])
        }
        return data
    }

    // MARK: - Response Parsing

    private func parseEvents(from data: Data) -> [CalendarEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let payload = (json["data"] as? [String: Any]) ?? json
        guard let items = payload["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseEvent($0) }
    }

    private func parseEvent(_ item: [String: Any]) -> CalendarEvent? {
        guard let id = item["id"] as? String,
              let summary = item["summary"] as? String,
              let startDict = item["start"] as? [String: Any],
              let endDict = item["end"] as? [String: Any]
        else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter2 = ISO8601DateFormatter()
        formatter2.formatOptions = [.withInternetDateTime]

        func parseDate(_ dict: [String: Any]) -> Date? {
            if let dt = dict["dateTime"] as? String {
                return formatter.date(from: dt) ?? formatter2.date(from: dt)
            }
            if let d = dict["date"] as? String {
                return ISO8601DateFormatter().date(from: d + "T00:00:00Z")
            }
            return nil
        }

        guard let start = parseDate(startDict), let end = parseDate(endDict) else { return nil }

        let attendees = (item["attendees"] as? [[String: Any]] ?? []).compactMap { a -> String? in
            guard a["self"] as? Bool != true else { return nil }
            return a["email"] as? String
        }

        let meetLink = (item["conferenceData"] as? [String: Any])
            .flatMap { $0["entryPoints"] as? [[String: Any]] }?
            .first { $0["entryPointType"] as? String == "video" }
            .flatMap { $0["uri"] as? String }

        return CalendarEvent(
            id: id,
            title: summary,
            startDate: start,
            endDate: end,
            attendeeEmails: attendees,
            meetLink: meetLink
        )
    }
}
