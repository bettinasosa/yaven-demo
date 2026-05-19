//
//  ComposioConnector.swift
//  leanring-buddy
//
//  Lightweight helper for triggering a Composio OAuth connection
//  from anywhere in the app (outside the onboarding flow).
//
//  Usage:
//    await ComposioConnector.connect(composioKey: "HUBSPOT", entityId: entityId)
//

import AppKit
import Foundation

@MainActor
enum ComposioConnector {

    #if DEBUG
    private static let workerBaseURL = "http://localhost:8787"
    #else
    private static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    enum ConnectResult {
        case connected
        case unsupported
        case timedOut
        case failed(String)
    }

    /// Initiates a Composio OAuth connection for the given tool.
    /// Opens the browser for OAuth, then polls until active (up to 3 minutes).
    static func connect(composioKey: String, entityId: String) async -> ConnectResult {
        guard let url = URL(string: "\(workerBaseURL)/connect") else {
            return .failed("Bad URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "appKey": composioKey,
            "entityId": entityId,
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .failed("Network error")
        }

        if json["unsupported"] as? Bool == true {
            return .unsupported
        }

        // Open the OAuth page in the browser.
        if let urlString = json["redirectUrl"] as? String,
           let redirectURL = URL(string: urlString) {
            NSWorkspace.shared.open(redirectURL)
        }

        guard let accountId = json["connectedAccountId"] as? String else {
            return .failed("No account ID")
        }

        // Poll for up to 3 minutes.
        guard let statusURL = URL(string: "\(workerBaseURL)/connection-status?id=\(accountId)") else {
            return .failed("Bad status URL")
        }

        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return .failed("Cancelled") }
            guard let (statusData, _) = try? await URLSession.shared.data(from: statusURL),
                  let statusJson = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                  statusJson["status"] as? String == "ACTIVE"
            else { continue }

            OnboardingManager.markToolConnected(composioKey)
            return .connected
        }

        return .timedOut
    }
}
