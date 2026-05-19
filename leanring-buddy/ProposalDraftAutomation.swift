//
//  ProposalDraftAutomation.swift
//  leanring-buddy
//
//  Reads a client brief and generates a full project proposal draft,
//  then saves it as a Gmail draft ready to send.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Phase

enum ProposalDraftPhase {
    case idle
    case generating
    case draft(ProposalResult)
    case savingDraft
    case saved
    case failed(String)
}

struct ProposalResult {
    let clientName: String
    let subject: String
    let body: String
    var recipientEmail: String = ""
}

// MARK: - Controller

@MainActor
final class ProposalDraftController: ObservableObject {

    @Published var phase: ProposalDraftPhase = .idle

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    func generate(brief: String) {
        guard !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        phase = .generating

        Task {
            do {
                let result = try await callClaude(brief: brief)
                phase = .draft(result)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func saveGmailDraft(result: ProposalResult) {
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

    private func callClaude(brief: String) async throws -> ProposalResult {
        guard let url = URL(string: "\(workerBaseURL)/chat") else { throw URLError(.badURL) }

        let profile = YavenStorage.readProfileText() ?? ""
        let userRole = YavenUserContext.shared.role

        let system = """
        You are Yaven, a freelance business assistant. Generate a professional project proposal from the client brief.
        Use the freelancer's profile for personalisation (name, rate, expertise).

        Return ONLY valid JSON — no markdown, no commentary:
        {
          "clientName": "inferred from brief",
          "subject": "Project Proposal: [project name]",
          "body": "Full proposal email body in plain text — include intro, scope understanding, key deliverables, timeline estimate, rate, and clear next steps."
        }
        """

        var context = "Client brief:\n\(brief)"
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

        return ProposalResult(
            clientName: parsed["clientName"] as? String ?? "Client",
            subject: parsed["subject"] as? String ?? "Project Proposal",
            body: parsed["body"] as? String ?? text
        )
    }

    private func createGmailDraft(to: String, subject: String, body: String) async throws {
        guard let url = URL(string: "\(workerBaseURL)/execute") else { throw URLError(.badURL) }
        let entityId = YavenUserContext.shared.entityId
        guard !entityId.isEmpty else { throw NSError(domain: "Yaven", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }

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

struct ProposalDraftView: View {
    @StateObject private var controller = ProposalDraftController()
    @State private var brief = ""
    @State private var recipientEmail = ""
    @FocusState private var briefFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch controller.phase {
                case .idle, .generating:
                    inputSection
                    if case .generating = controller.phase {
                        generatingRow
                    }

                case .draft(let result):
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
            label("Client brief")
            TextEditor(text: $brief)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .frame(minHeight: 90, maxHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .focused($briefFocused)
                .onAppear { briefFocused = true }

            label("Client email (optional)")
            TextField("client@example.com", text: $recipientEmail)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))

            actionButton("Generate Proposal", icon: "doc.badge.plus", color: .blue) {
                controller.generate(brief: brief)
            }
            .disabled(brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Result

    private func resultSection(_ result: ProposalResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 13))
                Text("Proposal ready for \(result.clientName)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Edit", action: { controller.reset() })
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                    .pointerCursor()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(result.subject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                ScrollView { Text(result.body).font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(2) }
                    .frame(height: 120)
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

            actionButton("Save to Gmail Drafts", icon: "envelope.badge.fill", color: .cyan) {
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

    private var generatingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Drafting proposal…").font(.system(size: 12)).foregroundColor(.secondary)
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
        Button("Start over") { controller.reset(); brief = ""; recipientEmail = "" }
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
