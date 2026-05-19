//
//  YavenWorkflowRegistry.swift
//  leanring-buddy
//
//  Describes available workflows and provides a central lookup.
//  Each WorkflowDefinition carries the metadata the UI needs to
//  render a chip/entry point and route the user into the right controller.
//

import Foundation

// MARK: - Definition

struct WorkflowDefinition {
    let id: WorkflowID
    let displayName: String
    let chipLabel: String
    let chipIcon: String      // SF Symbol name
    let description: String
}

// MARK: - Registry

final class YavenWorkflowRegistry {

    static let shared = YavenWorkflowRegistry()

    private init() {}

    private let definitions: [WorkflowID: WorkflowDefinition] = [
        .salesCallLogger: WorkflowDefinition(
            id: .salesCallLogger,
            displayName: "Log Sales Call",
            chipLabel: "Log Call",
            chipIcon: "phone.fill",
            description: "Extract call notes, update HubSpot, draft follow-up emails — all in one click."
        ),
        .preCallBrief: WorkflowDefinition(
            id: .preCallBrief,
            displayName: "Pre-Call Brief",
            chipLabel: "Brief",
            chipIcon: "doc.text.magnifyingglass",
            description: "Five minutes before each call, Yaven surfaces a 3-bullet brief: rapport hook, pain point, likely objection."
        ),
    ]

    func definition(for id: WorkflowID) -> WorkflowDefinition? {
        definitions[id]
    }

    var allDefinitions: [WorkflowDefinition] {
        definitions.values.sorted { $0.displayName < $1.displayName }
    }
}
