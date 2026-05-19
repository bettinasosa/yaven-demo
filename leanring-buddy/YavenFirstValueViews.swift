//
//  YavenFirstValueViews.swift
//  leanring-buddy
//

import SwiftUI

struct YavenFirstMessageView: View {
    let onYes: () -> Void
    let onLater: () -> Void

    @State private var messageOpacity: Double = 0
    @State private var buttonsOpacity: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hi. I'm here.")
                    .font(.custom("Fraunces-SemiBold", size: 21, relativeTo: .title3))
                Text("Want me to start by cleaning up your inbox?")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .opacity(messageOpacity)

            HStack(spacing: 12) {
                Button("Yes, let's do it", action: onYes)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button("Later", action: onLater)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .opacity(buttonsOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                messageOpacity = 1
            }
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(.easeOut(duration: 0.2)) {
                    buttonsOpacity = 1
                }
            }
        }
    }
}

struct ScanningProgressView: View {
    let lines: [String]
    let visibleLineCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading your inbox…")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index < visibleLineCount {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: visibleLineCount)
    }
}

struct CategoriesApprovalContainer: View {
    let plan: CleanupPlan
    let emailsByID: [String: RecentEmail]
    @ObservedObject var cleanupController: YavenCleanupController
    let onSkip: () -> Void

    @State private var batches: [CategorizedBatch]

    init(
        plan: CleanupPlan,
        emailsByID: [String: RecentEmail],
        cleanupController: YavenCleanupController,
        onSkip: @escaping () -> Void
    ) {
        self.plan = plan
        self.emailsByID = emailsByID
        self.cleanupController = cleanupController
        self.onSkip = onSkip
        _batches = State(initialValue: plan.batches)
    }

    var body: some View {
        CategoriesCardView(
            plan: CleanupPlan(batches: batches, totalReviewed: plan.totalReviewed),
            emailsByID: emailsByID,
            onArchiveAll: { batch in cleanupController.execute(batch: batch) },
            onFileReceipts: { batch in cleanupController.execute(batch: batch) },
            onDoAll: {
                cleanupController.executeAllDefaults(
                    for: CleanupPlan(batches: batches, totalReviewed: plan.totalReviewed)
                )
            },
            onSkip: onSkip,
            batches: $batches
        )
    }
}

struct CategoriesCardView: View {
    let plan: CleanupPlan
    let emailsByID: [String: RecentEmail]
    let onArchiveAll: (CategorizedBatch) -> Void
    let onFileReceipts: (CategorizedBatch) -> Void
    let onDoAll: () -> Void
    let onSkip: () -> Void

    @Binding var batches: [CategorizedBatch]
    @State private var expandedBatchID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("I went through your last \(plan.totalReviewed) emails. Here's what I found:")
                .font(.system(size: 14, weight: .semibold))

            ForEach($batches) { $batch in
                categoryRow($batch)
            }

            HStack {
                Button("Do all of the above", action: onDoAll)
                    .buttonStyle(.borderedProminent)

                Spacer()

                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private func categoryRow(_ batch: Binding<CategorizedBatch>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(batch.wrappedValue.category.displayEmoji)  \(batch.wrappedValue.summary)")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)

                categoryActions(batch)
            }

            if expandedBatchID == batch.wrappedValue.id {
                CategoryExpandedView(
                    batch: batch.wrappedValue,
                    emailsByID: emailsByID,
                    onExclude: { emailID in
                        batch.wrappedValue.excludedMessageIds.insert(emailID)
                    },
                    onArchive: { onArchiveAll(batch.wrappedValue) }
                )
            }
        }
    }

    @ViewBuilder
    private func categoryActions(_ batch: Binding<CategorizedBatch>) -> some View {
        let value = batch.wrappedValue
        switch value.defaultAction {
        case .archive:
            HStack(spacing: 8) {
                Button("Archive all") { onArchiveAll(value) }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                Button(expandedBatchID == value.id ? "Hide" : "Show emails") {
                    toggleExpandedBatch(value.id)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        case .moveToFolder:
            HStack(spacing: 8) {
                Button("File in Receipts") { onFileReceipts(value) }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                Button(expandedBatchID == value.id ? "Hide" : "Show emails") {
                    toggleExpandedBatch(value.id)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        case .surface:
            Button(expandedBatchID == value.id ? "Hide" : "Show emails") {
                toggleExpandedBatch(value.id)
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        case .leaveAlone:
            Text("Leave them")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func toggleExpandedBatch(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            expandedBatchID = expandedBatchID == id ? nil : id
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}

struct CategoryExpandedView: View {
    let batch: CategorizedBatch
    let emailsByID: [String: RecentEmail]
    let onExclude: (String) -> Void
    let onArchive: () -> Void

    private var previewEmails: [RecentEmail] {
        batch.effectiveMessageIds.prefix(5).compactMap { emailsByID[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if previewEmails.isEmpty {
                Text("No preview available for this group.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewEmails) { email in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(email.sender)
                                .font(.system(size: 12, weight: .semibold))
                            Text(email.subject)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            onExclude(email.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
            }

            if batch.defaultAction == .archive {
                Button("Archive") { onArchive() }
                    .buttonStyle(.bordered)
                    .pointerCursor()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

struct CleanupExecutionView: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CleanupDoneView: View {
    let archivedCount: Int
    let filedReceiptCount: Int
    let inboxCount: Int
    let needsReplyItems: [NeedsReplyItem]
    let onDraftReply: (NeedsReplyItem) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("✓ Done.")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointerCursor()
            }

            Text(doneSummary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if !needsReplyItems.isEmpty {
                Text("Your inbox now has \(inboxCount) emails. \(needsReplyItems.count) of them look like they need your attention:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                ForEach(needsReplyItems) { item in
                    HStack {
                        Text(item.actionDescription)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Draft reply") {
                            onDraftReply(item)
                        }
                        .buttonStyle(.bordered)
                        .pointerCursor()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("You can ask Yaven to do another pass any time by typing “clean up my inbox.”")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Ask Yaven something else") {
                    onContinue()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneSummary: String {
        var parts: [String] = []
        if archivedCount > 0 {
            parts.append("I archived \(archivedCount) emails")
        }
        if filedReceiptCount > 0 {
            parts.append("filed \(filedReceiptCount) receipts")
        }
        if parts.isEmpty {
            return "Your inbox is ready for a fresh pass whenever you want."
        }
        return parts.joined(separator: " and ") + "."
    }
}
