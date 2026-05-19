//
//  YavenTaskRunner.swift
//  leanring-buddy
//

import Combine
import Foundation

@MainActor
final class YavenTaskRunner: ObservableObject {
    typealias ThreadOperation = @MainActor (UUID) async -> Void
    typealias UIActionOperation = @MainActor () async -> YavenExecutionResult

    @Published private(set) var activeThreads: Set<UUID> = []
    @Published private(set) var queuedUIThreadIDs: [UUID] = []

    private struct UIActionJob {
        let threadID: UUID
        let operation: UIActionOperation
        let continuation: CheckedContinuation<YavenExecutionResult, Never>
    }

    private let store: YavenThreadStore
    private var tasksByThreadID: [UUID: Task<Void, Never>] = [:]
    private var uiActionQueue: [UIActionJob] = []
    private var isRunningUIAction = false

    init(store: YavenThreadStore? = nil) {
        self.store = store ?? .shared
        restoreIncompleteThreads()
    }

    func startThread(
        kind: YavenThreadKind,
        title: String,
        source: String? = nil,
        operation: @escaping ThreadOperation
    ) -> UUID {
        do {
            let thread = try store.createThread(
                kind: kind,
                title: title,
                status: .running,
                source: source
            )
            startExistingThread(thread.id, operation: operation)
            return thread.id
        } catch {
            print("YavenTaskRunner: could not create thread: \(error)")
            let fallbackID = UUID()
            startExistingThread(fallbackID, operation: operation)
            return fallbackID
        }
    }

    func startExistingThread(_ threadID: UUID, operation: @escaping ThreadOperation) {
        tasksByThreadID[threadID]?.cancel()
        activeThreads.insert(threadID)

        tasksByThreadID[threadID] = Task { [weak self] in
            await operation(threadID)
            await MainActor.run {
                self?.activeThreads.remove(threadID)
                self?.tasksByThreadID[threadID] = nil
            }
        }
    }

    func resumeThread(_ threadID: UUID, operation: @escaping ThreadOperation) {
        do {
            try store.updateThread(
                id: threadID,
                status: .running,
                requiresAttention: false
            )
        } catch {
            print("YavenTaskRunner: could not mark thread running: \(error)")
        }
        startExistingThread(threadID, operation: operation)
    }

    func approve(_ threadID: UUID, operation: @escaping ThreadOperation) {
        resumeThread(threadID, operation: operation)
    }

    func cancel(_ threadID: UUID) {
        tasksByThreadID[threadID]?.cancel()
        tasksByThreadID[threadID] = nil
        activeThreads.remove(threadID)
        uiActionQueue.removeAll { $0.threadID == threadID }
        queuedUIThreadIDs.removeAll { $0 == threadID }

        do {
            try store.updateThread(
                id: threadID,
                status: .cancelled,
                lastPreview: "Cancelled.",
                requiresAttention: false
            )
        } catch {
            print("YavenTaskRunner: could not cancel thread: \(error)")
        }
    }

    func runUIAction(
        threadID: UUID,
        operation: @escaping UIActionOperation
    ) async -> YavenExecutionResult {
        await withCheckedContinuation { continuation in
            uiActionQueue.append(
                UIActionJob(
                    threadID: threadID,
                    operation: operation,
                    continuation: continuation
                )
            )
            queuedUIThreadIDs = uiActionQueue.map(\.threadID)
            processNextUIAction()
        }
    }

    private func processNextUIAction() {
        guard !isRunningUIAction, !uiActionQueue.isEmpty else { return }
        isRunningUIAction = true
        let job = uiActionQueue.removeFirst()
        queuedUIThreadIDs = uiActionQueue.map(\.threadID)

        Task { [weak self] in
            let result = await job.operation()
            job.continuation.resume(returning: result)
            await MainActor.run {
                self?.isRunningUIAction = false
                self?.processNextUIAction()
            }
        }
    }

    private func restoreIncompleteThreads() {
        do {
            let threads = try store.recentThreads(limit: 100)
            for thread in threads {
                switch thread.status {
                case .running:
                    try store.updateThread(
                        id: thread.id,
                        status: .queued,
                        lastPreview: "Queued after relaunch.",
                        requiresAttention: false
                    )
                case .queued, .approvalRequired:
                    continue
                case .completed, .failed, .cancelled:
                    continue
                }
            }
        } catch {
            print("YavenTaskRunner: could not restore incomplete threads: \(error)")
        }
    }
}
