//
//  OnboardingManager.swift
//  leanring-buddy
//
//  Central ObservableObject for the three-stage onboarding flow.
//
//  Stage 1 — Google Sign In
//  Stage 2 — Form (name → work context → role → tools → time sinks)
//  Stage 3 — Optional connector connections
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class OnboardingManager: ObservableObject {

    // MARK: - Stage

    enum Stage: Equatable, Hashable {
        case googleSignIn
        case form
        case connections   // tool OAuth (Gmail essential, others optional)
        case connectors    // appearance picker
        case arrivalTransition
        case launchAnimation
        case complete
    }

    static let pendingFirstRunArrivalKey = "pendingFirstRunArrival"

    // MARK: - Published State

    @Published private(set) var stage: Stage

    // Stage 1
    @Published private(set) var isSigningInWithGoogle = false
    @Published private(set) var googleSignInErrorMessage: String?
    @Published private(set) var googleProfile: GoogleProfile?

    /// Called synchronously just before the Google OAuth session begins.
    var willStartSignIn: (() -> Void)?
    /// Called synchronously when sign-in ends (success, failure, or cancellation).
    var didFinishSignIn: (() -> Void)?

    /// Called just before opening a Composio OAuth URL in the browser.
    var willStartConnect: (() -> Void)?
    /// Called when a Composio OAuth connection completes or times out.
    var didFinishConnect: (() -> Void)?


    // Stage 3
    @Published private(set) var connectors: [OnboardingConnectorState] = []
    @Published private(set) var selectedAppearance: OnboardingAppearance = .cloud

    /// Screen-coordinate position of the tap that kicked off the arrival sequence.
    private(set) var arrivalClickOrigin: CGPoint = .zero

    // Final output — set when the form completes.
    @Published private(set) var userProfile: UserProfile?

    static let privacyNotice = "Yaven does not share or sell your data."

    // MARK: - Private

    private static let completionDefaultsKey = "hasCompletedOnboarding"
    private static let legacyDefaultsSuiteName = "com.humansongs.clicky"
    private static let entityIdKey = "yavenEntityId"
    private static let connectedToolKeysDefaultsKey = "connectedToolKeys"

    /// The Google email saved after sign-in. Persists across launches for returning users.
    static var savedEntityId: String? {
        UserDefaults.standard.string(forKey: entityIdKey)
    }

    /// Persisted set of Composio app keys that have been successfully connected.
    static var connectedToolKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: connectedToolKeysDefaultsKey) ?? [])
    }

    static func markToolConnected(_ composioKey: String) {
        var keys = connectedToolKeys
        keys.insert(composioKey.uppercased())
        UserDefaults.standard.set(Array(keys), forKey: connectedToolKeysDefaultsKey)
    }

    static func isToolConnected(_ composioKey: String) -> Bool {
        connectedToolKeys.contains(composioKey.uppercased())
    }

    private let googleAuthClient = GoogleAuthClient()
    private let profileMemoryManager: ProfileMemoryManager?

    // MARK: - Init

    init(profileMemoryManager: ProfileMemoryManager? = nil) {
        self.profileMemoryManager = profileMemoryManager
        if let savedAppearanceRaw = UserDefaults.standard.string(forKey: OnboardingAppearance.defaultsKey),
           let savedAppearance = OnboardingAppearance(rawValue: savedAppearanceRaw) {
            self.selectedAppearance = savedAppearance
        }
        if Self.hasCompletedOnboarding {
            self.stage = .complete
        } else {
            self.stage = .googleSignIn
        }
    }

    private static var hasCompletedOnboarding: Bool {
        if UserDefaults.standard.bool(forKey: completionDefaultsKey) { return true }
        let legacyDefaults = UserDefaults(suiteName: legacyDefaultsSuiteName)
        guard legacyDefaults?.bool(forKey: completionDefaultsKey) == true else { return false }
        UserDefaults.standard.set(true, forKey: completionDefaultsKey)
        return true
    }

    // MARK: - Stage 1: Google Sign In

    func startGoogleSignIn() {
        guard !isSigningInWithGoogle else { return }
        willStartSignIn?()
        isSigningInWithGoogle = true
        googleSignInErrorMessage = nil

        Task {
            do {
                let profile = try await googleAuthClient.signIn()
                googleProfile = profile
                UserDefaults.standard.set(profile.email, forKey: Self.entityIdKey)
                isSigningInWithGoogle = false
                didFinishSignIn?()
                stage = .form
            } catch GoogleAuthError.userCancelled {
                isSigningInWithGoogle = false
                didFinishSignIn?()
            } catch {
                isSigningInWithGoogle = false
                didFinishSignIn?()
                googleSignInErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Stage 2: Form

    /// Called by OnboardingFormView when the user completes all steps.
    func submitFormProfile(_ profile: UserProfile) {
        userProfile = profile
        YavenUserContext.shared.save(profile: profile)
        profileMemoryManager?.initializeFromOnboardingProfile(profile)
        buildConnectorStates(from: profile)
        stage = .connections
    }

    func proceedFromConnections() {
        stage = .connectors
    }

    // MARK: - Worker URL

    #if DEBUG
    private static let workerBaseURL = "http://localhost:8787"
    #else
    private static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    // MARK: - Stage 3: Connectors

    private func buildConnectorStates(from profile: UserProfile) {
        connectors = profile.tools.map { OnboardingConnectorState(tool: $0) }
    }

    func connectTool(composioKey: String) {
        guard connectors.first(where: { $0.composioKey == composioKey })?.status == .notConnected else { return }
        updateConnectorStatus(for: composioKey, to: .connecting)

        let entityId = googleProfile?.email ?? "anonymous"
        Task { await performConnect(composioKey: composioKey, entityId: entityId) }
    }

    func selectAppearance(_ appearance: OnboardingAppearance) {
        selectedAppearance = appearance
        UserDefaults.standard.set(appearance.rawValue, forKey: OnboardingAppearance.defaultsKey)
    }


    func skipConnectors() {
        for index in connectors.indices
            where connectors[index].status == .notConnected || connectors[index].status == .unsupported {
            connectors[index].status = .skipped
        }
        beginArrivalTransition()
    }

    func proceedFromConnectors(clickOrigin: CGPoint = .zero) {
        arrivalClickOrigin = clickOrigin
        beginArrivalTransition()
    }

    private func beginArrivalTransition() {
        UserDefaults.standard.set(selectedAppearance.rawValue, forKey: OnboardingAppearance.defaultsKey)
        UserDefaults.standard.set(true, forKey: Self.pendingFirstRunArrivalKey)
        stage = .arrivalTransition

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard stage == .arrivalTransition else { return }
            markOnboardingComplete()
        }
    }

    private func beginLaunchAnimation() {
        UserDefaults.standard.set(selectedAppearance.rawValue, forKey: OnboardingAppearance.defaultsKey)
        stage = .launchAnimation

        Task {
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            guard stage == .launchAnimation else { return }
            markOnboardingComplete()
        }
    }

    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: Self.completionDefaultsKey)
        stage = .complete
    }

    static var shouldRunFirstRunArrival: Bool {
        UserDefaults.standard.bool(forKey: pendingFirstRunArrivalKey)
    }

    static func clearFirstRunArrivalFlag() {
        UserDefaults.standard.set(false, forKey: pendingFirstRunArrivalKey)
    }

    private func updateConnectorStatus(for composioKey: String, to status: ConnectorStatus) {
        guard let index = connectors.firstIndex(where: { $0.composioKey == composioKey }) else { return }
        connectors[index].status = status
        if status == .connected {
            OnboardingManager.markToolConnected(composioKey)
        }
    }

    // MARK: - Composio OAuth

    private struct ConnectResponse: Codable {
        let connectionStatus: String?
        let connectedAccountId: String?
        let redirectUrl: String?
        let unsupported: Bool?
    }

    private struct StatusResponse: Codable {
        let status: String?
    }

    private func performConnect(composioKey: String, entityId: String) async {
        guard let url = URL(string: "\(Self.workerBaseURL)/connect") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "appKey": composioKey,
            "entityId": entityId,
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let response = try? JSONDecoder().decode(ConnectResponse.self, from: data) else {
            updateConnectorStatus(for: composioKey, to: .notConnected)
            return
        }

        // Worker returns unsupported:true when Composio has no managed credentials
        // for the toolkit (e.g. granola_mcp). Skip it silently.
        if response.unsupported == true {
            updateConnectorStatus(for: composioKey, to: .unsupported)
            return
        }

        guard response.redirectUrl != nil || response.connectedAccountId != nil else {
            updateConnectorStatus(for: composioKey, to: .unsupported)
            return
        }

        // Open the Composio OAuth page in the default browser.
        if let urlString = response.redirectUrl, let redirectURL = URL(string: urlString) {
            willStartConnect?()
            NSWorkspace.shared.open(redirectURL)
        }

        // Poll until the user completes OAuth (up to 3 minutes).
        if let accountId = response.connectedAccountId {
            await pollForConnection(composioKey: composioKey, accountId: accountId)
        }
        didFinishConnect?()
    }

    private func pollForConnection(composioKey: String, accountId: String) async {
        guard let url = URL(string: "\(Self.workerBaseURL)/connection-status?id=\(accountId)") else { return }

        for _ in 0..<60 { // 60 × 3 s = 3 minutes
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let result = try? JSONDecoder().decode(StatusResponse.self, from: data),
                  result.status == "ACTIVE" else { continue }
            updateConnectorStatus(for: composioKey, to: .connected)
            return
        }
        // Timed out — leave as connecting so the user can see something happened.
    }

    // MARK: - Debug

    #if DEBUG
    func debugSkipOnboarding() {
        markOnboardingComplete()
    }

    func resetOnboardingForTesting() {
        UserDefaults.standard.set(false, forKey: Self.completionDefaultsKey)
        UserDefaults.standard.set(false, forKey: Self.pendingFirstRunArrivalKey)
        googleProfile = nil
        userProfile = nil
        connectors = []
        selectedAppearance = .cloud
        isSigningInWithGoogle = false
        googleSignInErrorMessage = nil
        stage = .googleSignIn
    }
    #endif
}
