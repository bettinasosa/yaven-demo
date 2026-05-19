//
//  GmailComposioClient.swift
//  leanring-buddy
//
//  Async client for Gmail operations via Composio's action execution API.
//  All calls are proxied through the Cloudflare Worker at /composio-action.
//

import Foundation

struct GmailComposioClient {

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    let entityId: String

    // MARK: - Gmail Actions

    /// Fetches recent messages from the user's inbox.
    func listRecentEmails(limit: Int = 50) async throws -> [RecentEmail] {
        let data = try await execute(action: "GMAIL_FETCH_EMAILS", input: [
            "max_results": limit,
            "label_ids": ["INBOX"],
            "include_body": false,
            "query": "newer_than:30d",
        ])
        return parseEmailList(from: data)
    }

    /// Moves a message out of the inbox (archives it).
    func archiveEmail(messageId: String) async throws {
        _ = try await execute(action: "GMAIL_ARCHIVE_EMAIL", input: [
            "message_id": messageId,
        ])
    }

    /// Creates a Gmail draft addressed to a recipient.
    func createDraft(to recipient: String, subject: String, body: String) async throws {
        _ = try await execute(action: "GMAIL_CREATE_DRAFT_EMAIL", input: [
            "recipient_email": recipient,
            "subject": subject,
            "body": body,
        ])
    }

    // MARK: - Core HTTP

    private func execute(action: String, input: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(workerBaseURL)/execute") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // v3 format: actionSlug, entityId, arguments (matches Nick's /execute route)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "actionSlug": action,
            "entityId": entityId,
            "arguments": input,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            let detail = String(data: data, encoding: .utf8) ?? "no detail"
            throw NSError(domain: "GmailComposio", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(action) failed: \(detail)"
            ])
        }
        return data
    }

    // MARK: - Response Parsing

    private func parseEmailList(from data: Data) -> [RecentEmail] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        // Composio v3 wraps the Gmail response in "data"; v2 used "response_data".
        // Try all known envelope shapes.
        let payload = (json["data"] as? [String: Any])
                   ?? (json["response_data"] as? [String: Any])
                   ?? json
        guard let messages = payload["messages"] as? [[String: Any]] else { return [] }
        return messages.compactMap { parseMessage($0) }
    }

    private func parseMessage(_ msg: [String: Any]) -> RecentEmail? {
        guard let id = msg["id"] as? String else { return nil }
        let snippet = msg["snippet"] as? String ?? ""
        var sender = ""
        var subject = "(no subject)"
        var date = ""

        if let payload = msg["payload"] as? [String: Any],
           let headers = payload["headers"] as? [[String: Any]] {
            for header in headers {
                switch (header["name"] as? String ?? "").lowercased() {
                case "from":    sender  = header["value"] as? String ?? ""
                case "subject": subject = header["value"] as? String ?? "(no subject)"
                case "date":    date    = header["value"] as? String ?? ""
                default: break
                }
            }
        }
        return RecentEmail(id: id, sender: sender, subject: subject, date: date, snippet: snippet)
    }
}
