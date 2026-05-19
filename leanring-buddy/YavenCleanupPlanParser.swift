//
//  YavenCleanupPlanParser.swift
//  leanring-buddy
//

import Foundation

private struct ProposedCleanupCategory: Codable {
    let category: YavenCategory
    let messageIds: [String]
    let summary: String

    enum CodingKeys: String, CodingKey {
        case category
        case messageIds = "message_ids"
        case summary
    }
}

private struct ProposedCleanupPlanPayload: Codable {
    let categories: [ProposedCleanupCategory]
}

enum YavenCleanupPlanParser {
    static func decodePlan(from responseText: String, totalReviewed: Int) throws -> CleanupPlan {
        let jsonText = try extractJSONObject(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            throw parseError("Claude returned cleanup data that could not be converted to UTF-8.")
        }

        let payload = try JSONDecoder().decode(ProposedCleanupPlanPayload.self, from: data)
        let batches = payload.categories.compactMap { proposed -> CategorizedBatch? in
            guard !proposed.messageIds.isEmpty else { return nil }
            return CategorizedBatch(
                category: proposed.category,
                messageIds: proposed.messageIds,
                summary: proposed.summary,
                defaultAction: defaultAction(for: proposed.category)
            )
        }

        return CleanupPlan(batches: batches, totalReviewed: totalReviewed)
    }

    static func decodeNeedsReplyItems(from responseText: String) throws -> [NeedsReplyItem] {
        let jsonText = try extractJSONObject(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            throw parseError("Claude returned needs-reply data that could not be converted to UTF-8.")
        }

        if let items = try? JSONDecoder().decode([NeedsReplyItemPayload].self, from: data) {
            return items.map {
                NeedsReplyItem(
                    id: $0.id,
                    sender: $0.sender,
                    subject: $0.subject,
                    actionDescription: $0.actionDescription
                )
            }
        }

        let wrapped = try JSONDecoder().decode(NeedsReplyItemsWrapper.self, from: data)
        return wrapped.items.map {
            NeedsReplyItem(
                id: $0.id,
                sender: $0.sender,
                subject: $0.subject,
                actionDescription: $0.actionDescription
            )
        }
    }

    private static func defaultAction(for category: YavenCategory) -> CleanupAction {
        switch category {
        case .newsletters, .promotions:
            return .archive
        case .needsReply:
            return .surface
        case .receipts:
            return .moveToFolder("Receipts")
        case .personalWork:
            return .leaveAlone
        }
    }

    private static func extractJSONObject(from responseText: String) throws -> String {
        if let fencedRange = responseText.range(of: #"```(?:json)?\s*(\{[\s\S]*?\})\s*```"#, options: .regularExpression) {
            var fenced = String(responseText[fencedRange])
            fenced = fenced.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            fenced = fenced.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            return fenced
        }

        if let firstBrace = responseText.firstIndex(of: "{"),
           let lastBrace = responseText.lastIndex(of: "}") {
            return String(responseText[firstBrace...lastBrace])
        }

        if let firstBracket = responseText.firstIndex(of: "["),
           let lastBracket = responseText.lastIndex(of: "]") {
            return String(responseText[firstBracket...lastBracket])
        }

        throw parseError("Claude did not return structured cleanup JSON.")
    }

    private static func parseError(_ message: String) -> NSError {
        NSError(domain: "YavenCleanupPlanParser", code: -1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}

private struct NeedsReplyItemPayload: Codable {
    let id: String
    let sender: String
    let subject: String
    let actionDescription: String

    enum CodingKeys: String, CodingKey {
        case id
        case sender
        case subject
        case actionDescription = "action_description"
    }
}

private struct NeedsReplyItemsWrapper: Codable {
    let items: [NeedsReplyItemPayload]
}
