//
//  Signal.swift
//  leanring-buddy
//
//  A single user-feedback event. Written to signals.jsonl each time the user
//  accepts, edits, or rejects something Yaven produces.
//

import Foundation

struct Signal: Codable {
    let timestamp: Date
    let type: SignalType
    let action: SignalAction
    let yavenOutput: String
    let finalOutput: String
    let context: String

    enum CodingKeys: String, CodingKey {
        case timestamp, type, action, context
        case yavenOutput = "yaven_output"
        case finalOutput = "final_output"
    }
}

enum SignalType: String, Codable {
    case messageDraft = "message_draft"
    case icpCheck = "icp_check"
    case action
}

enum SignalAction: String, Codable {
    case accepted
    case edited
    case rejected
}
