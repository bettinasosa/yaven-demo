//
//  YavenSkillRegistry.swift
//  leanring-buddy
//

import Foundation

enum YavenSkillKind {
    case read
    case write(requiresApproval: Bool)
    case structuredOutput

    var requiresApproval: Bool {
        switch self {
        case .write(let requiresApproval):
            return requiresApproval
        case .read, .structuredOutput:
            return false
        }
    }
}

struct YavenSkill {
    let name: String
    let kind: YavenSkillKind
    var risk: YavenActionRisk = .low
    var inputSchema: String?
    var outputSchema: String?
    let run: ([String: Any]) throws -> String
}

struct YavenSkillRegistry {
    static let shared = YavenSkillRegistry()

    private let skills: [String: YavenSkill]

    init() {
        let mailSkills = MailSkills.makeAll()
        let hubSpotSkills = HubSpotSkills.makeAll()
        var registry: [String: YavenSkill] = [:]
        for skill in mailSkills + hubSpotSkills {
            registry[skill.name] = skill
        }
        skills = registry
    }

    func skill(named name: String) -> YavenSkill? {
        skills[name]
    }

    func run(name: String, input: [String: Any]) throws -> String {
        guard let skill = skills[name] else {
            throw NSError(domain: "YavenSkillRegistry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unknown skill: \(name)"
            ])
        }
        return try skill.run(input)
    }
}
