//
//  YavenCleanupController.swift
//  leanring-buddy
//

import Combine
import Foundation

@MainActor
final class YavenCleanupController: ObservableObject {
    @Published private(set) var phase: YavenCleanupPhase = .idle

    #if DEBUG
    private static let workerBaseURL = "http://localhost:8787"
    #else
    private static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    private lazy var claudeAPI = ClaudeAPI(proxyURL: "\(Self.workerBaseURL)/chat")
    private var currentTask: Task<Void, Never>?
    private var storedEmailsByID: [String: RecentEmail] = [:]
    private var storedPlan: CleanupPlan?
    private var gmailClient: GmailComposioClient?

    func start(entityId: String) {
        gmailClient = GmailComposioClient(entityId: entityId)
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.runCleanupFlow()
        }
    }

    var onSkipped: (() -> Void)?

    func skip() {
        currentTask?.cancel()
        phase = .skipped
        onSkipped?()
    }

    func executeAllDefaults(for plan: CleanupPlan) {
        execute(batches: plan.batches)
    }

    func execute(batch: CategorizedBatch) {
        execute(batches: [batch])
    }

    private func runCleanupFlow() async {
        let scanningLines = [
            "Connecting to Gmail…",
            "Reading your last 50 emails…",
            "Looking for patterns…",
            "Sorting by what's important…"
        ]

        phase = .scanning(lines: scanningLines, visibleLineCount: 0)

        do {
            for index in scanningLines.indices {
                try await Task.sleep(nanoseconds: UInt64(scanningDelayNanoseconds(for: index)))
                guard !Task.isCancelled else { return }
                phase = .scanning(lines: scanningLines, visibleLineCount: index + 1)
            }

            guard let client = gmailClient else {
                phase = .error("Gmail is not connected. Please connect your Gmail account in settings.")
                return
            }

            let emails = try await client.listRecentEmails(limit: 50)
            storedEmailsByID = Dictionary(uniqueKeysWithValues: emails.map { ($0.id, $0) })

            let planResponse = try await claudeAPI.sendTextRequest(
                systemPrompt: Self.cleanupSystemPrompt,
                userPrompt: Self.cleanupUserPrompt(emails: emails)
            )

            let plan = try YavenCleanupPlanParser.decodePlan(
                from: planResponse,
                totalReviewed: min(emails.count, 50)
            )
            storedPlan = plan
            phase = .awaitingApproval(plan, emailsByID: storedEmailsByID)
        } catch is CancellationError {
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func execute(batches: [CategorizedBatch]) {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.runExecution(batches: batches)
        }
    }

    private func runExecution(batches: [CategorizedBatch]) async {
        guard let client = gmailClient else {
            phase = .error("Gmail client is not initialised.")
            return
        }

        var progressLines: [String] = []
        var archivedCount = 0
        var needsReplyIDs: [String] = []

        phase = .executing(lines: progressLines)

        for batch in batches {
            let ids = batch.effectiveMessageIds
            guard !ids.isEmpty else { continue }

            switch batch.defaultAction {
            case .archive, .moveToFolder:
                // Gmail has no folders — treat both as archive (remove from inbox).
                let label = batch.defaultAction == .archive
                    ? batch.category.displayTitle
                    : "receipts and confirmations"
                progressLines.append("Archiving \(ids.count) \(label)…")
                phase = .executing(lines: progressLines)

                var archived = 0
                for id in ids {
                    guard !Task.isCancelled else { return }
                    if (try? await client.archiveEmail(messageId: id)) != nil { archived += 1 }
                }
                archivedCount += archived
                progressLines[progressLines.count - 1] = "Archived \(archived) email(s)."

            case .surface:
                needsReplyIDs.append(contentsOf: ids)

            case .leaveAlone:
                continue
            }

            phase = .executing(lines: progressLines)
        }

        let needsReplyItems = loadNeedsReplyItems(messageIDs: needsReplyIDs)

        phase = .done(
            archivedCount: archivedCount,
            filedReceiptCount: 0,
            inboxCount: 0,
            needsReplyItems: needsReplyItems
        )
    }

    private func loadNeedsReplyItems(messageIDs: [String]) -> [NeedsReplyItem] {
        messageIDs.compactMap { id -> NeedsReplyItem? in
            guard let email = storedEmailsByID[id] else { return nil }
            return NeedsReplyItem(
                id: email.id,
                sender: email.sender,
                subject: email.subject,
                actionDescription: "Reply to \(email.sender) about \"\(email.subject)\""
            )
        }
    }

    private func scanningDelayNanoseconds(for index: Int) -> UInt64 {
        switch index {
        case 0: return 300_000_000
        case 1: return 600_000_000
        case 2: return 500_000_000
        default: return 400_000_000
        }
    }

    private static let cleanupSystemPrompt = """
    You are Yaven, helping the user clean up their inbox. You have a list of their recent emails.

    Your job is to categorize each email into exactly one of these five categories:
    - newsletters: regular sends from newsletters, content publications, news roundups
    - promotions: marketing emails, sales pitches, discount offers, "limited time" emails
    - needs_reply: emails from real humans that contain a question, request, or expectation of a reply that hasn't happened yet
    - receipts: order confirmations, invoices, payment receipts, shipping notifications, account verifications
    - personal_work: real correspondence with colleagues, friends, or family that doesn't need an immediate reply

    Be conservative on "needs_reply" — only flag something if it's genuinely waiting on the user. When in doubt, put it in personal_work.

    Return only strict JSON. Do not use markdown. Do not include commentary outside JSON.

    JSON schema:
    {
      "categories": [
        {
          "category": "newsletters|promotions|needs_reply|receipts|personal_work",
          "message_ids": ["id1", "id2"],
          "summary": "47 newsletters from 12 senders"
        }
      ]
    }

    Every input email id must appear in exactly one category.
    """

    private static func cleanupUserPrompt(emails: [RecentEmail]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let emailJSON = (try? String(data: encoder.encode(emails), encoding: .utf8)) ?? "[]"
        return "Categorize these emails:\n\(emailJSON)"
    }
}
