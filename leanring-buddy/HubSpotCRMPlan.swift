//
//  HubSpotCRMPlan.swift
//  leanring-buddy
//

import Combine
import Foundation

struct HubSpotCRMUpdatePlan: Codable, Equatable {
    let goal: String
    let summary: String
    let actions: [HubSpotCRMPlannedAction]
}

struct HubSpotCRMPlannedAction: Codable, Identifiable, Equatable {
    var id = UUID()
    let skillName: String
    let summary: String
    let input: [String: String]

    enum CodingKeys: String, CodingKey {
        case skillName = "skill_name"
        case summary
        case input
    }
}
