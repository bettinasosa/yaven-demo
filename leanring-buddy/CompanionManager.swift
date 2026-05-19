//
//  CompanionManager.swift
//  leanring-buddy
//
//  Central state manager for the menu-bar panel. Owns screen permissions,
//  screenshot capture, Claude streaming, and typed chat state.
//

import Foundation
import Combine
import ScreenCaptureKit
import SwiftUI

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasScreenContentPermission = false
    @Published private(set) var isRequestingScreenContentPermission = false
    @Published private(set) var isProcessingResponse = false
    @Published var latestResponseText = ""

    /// The Claude model used for typed responses. Persisted to UserDefaults.
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"

    /// Base URL for the Cloudflare Worker proxy. All API requests route
    /// through this so keys never ship in the app binary.
    #if DEBUG
    private static let workerBaseURL = "http://localhost:8787"
    #else
    private static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    private var chatSystemPrompt: String {
        let base = """
        You are a concise assistant in a macOS menu-bar app. The user sends typed messages, and the app may include screenshots of their current screens for context.

        Rules:
        - Answer directly and practically.
        - Use the screenshots when they are relevant to the user's message.
        - If the screenshots are not relevant, answer from the user's text alone.
        - Do not claim capabilities beyond typed screen-aware chat.
        - Do not include hidden control tags or coordinate tags.
        """
        guard let profile = YavenStorage.readProfileText(), !profile.isEmpty else { return base }
        return "User context:\n\(profile)\n\n---\n\n\(base)"
    }

    private lazy var claudeAPI: ClaudeAPI = {
        ClaudeAPI(proxyURL: "\(Self.workerBaseURL)/chat", model: selectedModel)
    }()

    /// Conversation history so Claude can keep context within the current app session.
    private var conversationHistory: [(userMessage: String, assistantResponse: String)] = []
    private var currentResponseTask: Task<Void, Never>?
    private var permissionPollingTimer: Timer?

    var allPermissionsGranted: Bool {
        hasScreenRecordingPermission && hasScreenContentPermission
    }

    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedClaudeModel")
        claudeAPI.model = model
    }

    func start() {
        refreshAllPermissions()
        startPermissionPolling()

        // Eagerly touch the Claude API so its TLS warmup handshake completes
        // before the first user message.
        _ = claudeAPI
    }

    func stop() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
    }

    func refreshAllPermissions() {
        let previouslyHadScreenRecordingPermission = hasScreenRecordingPermission
        let previouslyHadAllPermissions = allPermissionsGranted

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadScreenRecordingPermission && hasScreenRecordingPermission {
            ClickyAnalytics.trackPermissionGranted(permission: "screen_recording")
        }

        if !previouslyHadAllPermissions && allPermissionsGranted {
            ClickyAnalytics.trackAllPermissionsGranted()
        }
    }

    func requestScreenContentPermission() {
        guard !isRequestingScreenContentPermission else { return }

        isRequestingScreenContentPermission = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    isRequestingScreenContentPermission = false
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = 320
                configuration.height = 240

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let didCaptureScreenContent = image.width > 0 && image.height > 0

                isRequestingScreenContentPermission = false
                guard didCaptureScreenContent else { return }

                hasScreenContentPermission = true
                UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")
                ClickyAnalytics.trackPermissionGranted(permission: "screen_content")

                if allPermissionsGranted {
                    ClickyAnalytics.trackAllPermissionsGranted()
                }
            } catch {
                print("Screen content permission request failed: \(error)")
                isRequestingScreenContentPermission = false
            }
        }
    }

    func submitTextMessage(_ messageText: String) {
        let trimmedMessageText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessageText.isEmpty else { return }

        latestResponseText = ""
        ClickyAnalytics.trackUserMessageSent(message: trimmedMessageText)
        sendTextMessageWithScreenshots(trimmedMessageText)
    }

    private func startPermissionPolling() {
        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    private func sendTextMessageWithScreenshots(_ messageText: String) {
        currentResponseTask?.cancel()

        currentResponseTask = Task {
            isProcessingResponse = true
            latestResponseText = ""

            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
                guard !Task.isCancelled else { return }

                let labeledImages = screenCaptures.map { screenCapture in
                    let dimensionInfo = " (image dimensions: \(screenCapture.screenshotWidthInPixels)x\(screenCapture.screenshotHeightInPixels) pixels)"
                    return (data: screenCapture.imageData, label: screenCapture.label + dimensionInfo)
                }

                let historyForAPI = conversationHistory.map { conversationEntry in
                    (
                        userPlaceholder: conversationEntry.userMessage,
                        assistantResponse: conversationEntry.assistantResponse
                    )
                }

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: chatSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: messageText,
                    onTextChunk: { [weak self] accumulatedResponseText in
                        self?.latestResponseText = accumulatedResponseText
                    }
                )

                guard !Task.isCancelled else { return }

                conversationHistory.append((
                    userMessage: messageText,
                    assistantResponse: fullResponseText
                ))

                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                ClickyAnalytics.trackAIResponseReceived(response: fullResponseText)
            } catch is CancellationError {
                // A newer message superseded this response.
            } catch {
                ClickyAnalytics.trackResponseError(error: error.localizedDescription)
                print("Claude response error: \(error)")
                latestResponseText = "Something went wrong. Check the console for details."
            }

            if !Task.isCancelled {
                isProcessingResponse = false
            }
        }
    }
}
