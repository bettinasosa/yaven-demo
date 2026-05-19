//
//  UserProfile.swift
//  leanring-buddy
//
//  Data models shared across the onboarding pipeline.
//  All types are Codable so they can be written to disk.
//

import Foundation

// MARK: - Google Auth Output

struct GoogleProfile {
    let name: String
    let email: String
}

// MARK: - Work Context

enum WorkContext: String, Codable, CaseIterable {
    case company
    case freelance
    case building
    case personal

    var displayLabel: String {
        switch self {
        case .company:   return "At a company"
        case .freelance: return "Freelancing / consulting"
        case .building:  return "Building something"
        case .personal:  return "Just for me"
        }
    }

    var needsName: Bool { self == .company || self == .building }

    var namePlaceholder: String {
        switch self {
        case .company:   return "Company name"
        case .building:  return "Project or startup name"
        default:         return ""
        }
    }
}

// MARK: - Tool

struct Tool: Codable {
    let name: String
    let composioKey: String
    let logo: String

    init(name: String, composioKey: String, logo: String = "") {
        self.name = name
        self.composioKey = composioKey
        self.logo = logo
    }

    enum CodingKeys: String, CodingKey {
        case name
        case composioKey = "composio_key"
        case logo
    }

    // Handles stored profiles that pre-date the logo field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        composioKey = try c.decode(String.self, forKey: .composioKey)
        logo = (try? c.decode(String.self, forKey: .logo)) ?? ""
    }
}

// MARK: - User Profile

struct UserProfile: Codable {
    let name: String
    let email: String
    let workContext: WorkContext
    let company: String
    let role: String
    let tools: [Tool]
    let automations: [String]

    enum CodingKeys: String, CodingKey {
        case name, email, role, company, tools, automations
        case workContext = "work_context"
    }
}

// MARK: - Connector State

enum ConnectorStatus {
    case notConnected
    case connecting
    case connected
    case skipped
    case unsupported  // toolkit has no Composio managed credentials
}

struct OnboardingConnectorState: Identifiable {
    let id: String           // composioKey
    let name: String
    let composioKey: String
    let logo: String
    var status: ConnectorStatus

    init(tool: Tool) {
        self.id = tool.composioKey
        self.name = tool.name
        self.composioKey = tool.composioKey
        self.logo = tool.logo
        self.status = .notConnected
    }
}

// MARK: - Stage 3: Appearance Choice

enum OnboardingAppearance: String, CaseIterable, Identifiable {
    case water
    case cloud

    var id: String { rawValue }
    static let defaultsKey = "selectedYavenAppearance"

    var displayName: String {
        switch self {
        case .water: return "Orb"
        case .cloud: return "Cloud"
        }
    }

    var tagline: String {
        switch self {
        case .water: return "Glassy, calm, minimal."
        case .cloud: return "Cute, light, floaty."
        }
    }
}
