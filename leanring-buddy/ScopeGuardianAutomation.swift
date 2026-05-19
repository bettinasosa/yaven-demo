//
//  ScopeGuardianAutomation.swift
//  leanring-buddy
//
//  Compares a client request against the original project scope.
//  Claude flags scope creep and drafts a professional boundary-setting reply,
//  then saves it as a Gmail draft ready to send.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Phase

enum ScopeGuardianPhase {
    case idle
    case analyzing
    case result(ScopeGuardianResult)
    case savingDraft
    case saved
    case failed(String)
}

struct ScopeGuardianResult {
    enum Verdict {
        case inScope, outOfScope, partiallyOutOfScope
    }
    let verdict: Verdict
    let reasoning: String
    let clientName: String
    let subject: String
    let body: String
    var recipientEmail: String = ""

    var verdictLabel: String {
        switch verdict {
        case .inScope:              return "In scope"
        case .outOfScope:           return "Out of scope"
        case .partiallyOutOfScope:  return "Partial scope creep"
        }
    }

    var verdictColor: Color {
        switch verdict {
        case .inScope:              return .green
        case .outOfScope:           return .red
        case .partiallyOutOfScope:  return .orange
        }
    }

    var verdictIcon: String {
        switch verdict {
        case .inScope:              return "checkmark.circle.fill"
        case .outOfScope:           return "xmark.circle.fill"
        case .partiallyOutOfScope:  return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Controller

@MainActor
final class ScopeGuardianController: ObservableObject {

    @Published var phase: ScopeGuardianPhase = .idle

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    func analyze(clientRequest: String, originalScope: String, clientName: String) {
        guard !clientRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !originalScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        phase = .analyzing

        Task {
            do {
                let result = try await callClaude(
                    clientRequest: clientRequest,
                    originalScope: originalScope,
                    clientName: clientName
                )
                phase = .result(result)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func saveGmailDraft(result: ScopeGuardianResult) {
        phase = .savingDraft

        Task {
            do {
                try await createGmailDraft(to: result.recipientEmail, subject: result.subject, body: result.body)
                phase = .saved
            } catch {
                phase = .failed("Gmail draft failed: \(error.localizedDescription)")
            }
        }
    }

    func reset() { phase = .idle }

    private func callClaude(clientRequest: String, originalScope: String, clientName: String) async throws -> ScopeGuardianResult {
        guard let url = URL(string: "\(workerBaseURL)/chat") else { throw URLError(.badURL) }

        let profile = YavenStorage.readProfileText() ?? ""
        let userRole = YavenUserContext.shared.role

        let system = """
        You are Yaven, a freelance business assistant. Your job is to protect the freelancer's scope.

        Given a client request and the original agreed scope, determine:
        1. Whether the request is IN_SCOPE, OUT_OF_SCOPE, or PARTIALLY_OUT_OF_SCOPE
        2. A brief reasoning (1-2 sentences)
        3. A professional email response — if in scope, acknowledge and confirm timeline; if out of scope or partial, explain politely that this falls outside the original agreement and propose options (change order or separate quote).

        Return ONLY valid JSON — no markdown, no commentary:
        {
          "verdict": "IN_SCOPE" | "OUT_OF_SCOPE" | "PARTIALLY_OUT_OF_SCOPE",
          "reasoning": "1-2 sentence explanation",
          "clientName": "the client name",
          "subject": "Re: [short description of request]",
          "body": "Full email body in plain text — professional, warm but clear."
        }
        """

        var context = "Client name: \(clientName.isEmpty ? "Client" : clientName)"
        context += "\n\nOriginal agreed scope:\n\(originalScope)"
        context += "\n\nClient's new request:\n\(clientRequest)"
        if !userRole.isEmpty { context += "\n\nFreelancer role: \(userRole)" }
        if !profile.isEmpty { context += "\n\nFreelancer profile:\n\(profile)" }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 800,
            "system": system,
            "messages": [["role": "user", "content": context]],
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { throw URLError(.cannotParseResponse) }

        let verdictString = parsed["verdict"] as? String ?? "OUT_OF_SCOPE"
        let verdict: ScopeGuardianResult.Verdict = {
            switch verdictString {
            case "IN_SCOPE":             return .inScope
            case "PARTIALLY_OUT_OF_SCOPE": return .partiallyOutOfScope
            default:                     return .outOfScope
            }
        }()

        return ScopeGuardianResult(
            verdict: verdict,
            reasoning: parsed["reasoning"] as? String ?? "",
            clientName: parsed["clientName"] as? String ?? clientName,
            subject: parsed["subject"] as? String ?? "Re: Your request",
            body: parsed["body"] as? String ?? text
        )
    }

    private func createGmailDraft(to: String, subject: String, body: String) async throws {
        guard let url = URL(string: "\(workerBaseURL)/execute") else { throw URLError(.badURL) }
        let entityId = YavenUserContext.shared.entityId
        guard !entityId.isEmpty else {
            throw NSError(domain: "Yaven", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let payload: [String: Any] = [
            "actionSlug": "GMAIL_CREATE_DRAFT",
            "entityId": entityId,
            "arguments": ["recipient_email": to, "subject": subject, "body": body],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}

// MARK: - View

struct ScopeGuardianView: View {
    @StateObject private var controller = ScopeGuardianController()
    @State private var clientName = ""
    @State private var originalScope = ""
    @State private var clientRequest = ""
    @State private var recipientEmail = ""
    @FocusState private var scopeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch controller.phase {
                case .idle, .analyzing:
                    inputSection
                    if case .analyzing = controller.phase {
                        analyzingRow
                    }

                case .result(let result):
                    resultSection(result)

                case .savingDraft:
                    statusRow("Saving to Gmail Drafts…", color: .cyan)

                case .saved:
                    statusRow("Draft saved to Gmail ✓", color: .green)
                    resetButton

                case .failed(let msg):
                    errorRow(msg)
                    resetButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Client name (optional)")
            TextField("Acme Corp", text: $clientName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))

            label("Original agreed scope")
            TextEditor(text: $originalScope)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .frame(minHeight: 70, maxHeight: 90)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .focused($scopeFocused)
                .onAppear { scopeFocused = true }

            label("Client's new request")
            TextEditor(text: $clientRequest)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .frame(minHeight: 60, maxHeight: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))

            label("Client email (optional)")
            TextField("client@example.com", text: $recipientEmail)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))

            actionButton("Analyse Scope", icon: "shield.lefthalf.filled", color: .purple) {
                controller.analyze(
                    clientRequest: clientRequest,
                    originalScope: originalScope,
                    clientName: clientName
                )
            }
            .disabled(
                clientRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                originalScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    // MARK: - Result

    private func resultSection(_ result: ScopeGuardianResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Verdict banner
            HStack(spacing: 10) {
                Image(systemName: result.verdictIcon)
                    .font(.system(size: 20))
                    .foregroundColor(result.verdictColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.verdictLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(result.verdictColor)
                    if !result.reasoning.isEmpty {
                        Text(result.reasoning)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button("Edit", action: { controller.reset() })
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                    .pointerCursor()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(result.verdictColor.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(result.verdictColor.opacity(0.20), lineWidth: 0.5))

            // Email preview
            VStack(alignment: .leading, spacing: 4) {
                Text(result.subject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                ScrollView { Text(result.body).font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(2) }
                    .frame(height: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.09), lineWidth: 0.5))

            if result.recipientEmail.isEmpty {
                label("Client email (to save draft)")
                TextField("client@example.com", text: $recipientEmail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            }

            actionButton("Save to Gmail Drafts", icon: "shield.lefthalf.filled", color: .purple) {
                var r = result
                r.recipientEmail = recipientEmail
                controller.saveGmailDraft(result: r)
            }
        }
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
    }

    private var analyzingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Analysing scope…").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private func statusRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private func errorRow(_ msg: String) -> some View {
        Text(msg).font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
            .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.07)))
    }

    private var resetButton: some View {
        Button("Start over") {
            controller.reset()
            clientName = ""; originalScope = ""; clientRequest = ""; recipientEmail = ""
        }
        .font(.system(size: 12)).foregroundColor(.secondary).buttonStyle(.plain).pointerCursor()
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.30), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
