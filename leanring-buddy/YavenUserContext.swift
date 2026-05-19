//
//  YavenUserContext.swift
//  leanring-buddy
//
//  Persists the user's role and selected tools across launches so the
//  widget bar can decide which automation widgets to surface without
//  re-running onboarding.
//
//  Call save(profile:) once when the onboarding form is submitted.
//  All reads are synchronous and safe on any thread.
//

import Foundation

final class YavenUserContext {

    static let shared = YavenUserContext()

    private static let roleKey      = "yavenUserRole"
    private static let toolsKey     = "yavenUserToolKeys"
    private static let entityIdKey  = "yavenEntityId"
    private static let firstNameKey = "yavenUserFirstName"

    private init() {}

    // MARK: - Write (called from OnboardingManager)

    func save(profile: UserProfile) {
        UserDefaults.standard.set(profile.role, forKey: Self.roleKey)
        let keys = profile.tools.map(\.composioKey)
        UserDefaults.standard.set(keys, forKey: Self.toolsKey)
        let firstName = profile.name.components(separatedBy: " ").first ?? profile.name
        UserDefaults.standard.set(firstName, forKey: Self.firstNameKey)
    }

    func saveEntityId(_ email: String) {
        UserDefaults.standard.set(email, forKey: Self.entityIdKey)
    }

    // MARK: - Read

    var role: String {
        UserDefaults.standard.string(forKey: Self.roleKey) ?? ""
    }

    var savedToolKeys: [String] {
        UserDefaults.standard.stringArray(forKey: Self.toolsKey) ?? []
    }

    /// The Composio entity ID — the user's Google email saved at sign-in.
    var entityId: String {
        UserDefaults.standard.string(forKey: Self.entityIdKey) ?? ""
    }

    var firstName: String {
        UserDefaults.standard.string(forKey: Self.firstNameKey) ?? ""
    }

    // MARK: - Derived signals

    /// True when the user's role string suggests a sales or BDR function.
    var isInSalesRole: Bool {
        let keywords = [
            "sales", "bdr", "sdr", "account executive", "ae",
            "account manager", "am", "business development",
            "revenue", "growth", "closing", "gtm"
        ]
        let lower = role.lowercased()
        return keywords.contains(where: { lower.contains($0) })
    }

    /// True when the user selected HubSpot during onboarding.
    var hasHubSpotTool: Bool {
        savedToolKeys.contains(where: { $0.uppercased().contains("HUBSPOT") })
    }

    /// True when the Log Call / HubSpot widget should be shown.
    var showHubSpotAutomations: Bool {
        isInSalesRole && hasHubSpotTool
    }
}
