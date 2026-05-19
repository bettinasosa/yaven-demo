//
//  leanring_buddyTests.swift
//  leanring-buddyTests
//
//  Created by thorfinn on 3/2/26.
//

import Foundation
import Testing
@testable import leanring_buddy

struct leanring_buddyTests {

    @Test func firstPermissionRequestUsesSystemPromptOnly() async throws {
        let presentationDestination = WindowPositionManager.permissionRequestPresentationDestination(
            hasPermissionNow: false,
            hasAttemptedSystemPrompt: false
        )

        #expect(presentationDestination == .systemPrompt)
    }

    @Test func repeatedPermissionRequestOpensSystemSettings() async throws {
        let presentationDestination = WindowPositionManager.permissionRequestPresentationDestination(
            hasPermissionNow: false,
            hasAttemptedSystemPrompt: true
        )

        #expect(presentationDestination == .systemSettings)
    }

    @Test func knownGrantedScreenRecordingPermissionSkipsTheGate() async throws {
        let shouldTreatPermissionAsGranted = WindowPositionManager.shouldTreatScreenRecordingPermissionAsGrantedForSessionLaunch(
            hasScreenRecordingPermissionNow: false,
            hasPreviouslyConfirmedScreenRecordingPermission: true
        )

        #expect(shouldTreatPermissionAsGranted)
    }

    @Test func directOpenParserAcceptsPoliteMailRequest() async throws {
        let openTarget = YavenOpenCommandResolver.openTarget(from: "Can you open the Mail app?")

        #expect(openTarget == .application(name: "Mail"))
    }

    @Test func directOpenParserAcceptsOpenUpArcRequest() async throws {
        let openTarget = YavenOpenCommandResolver.openTarget(from: "please open up Arc")

        #expect(openTarget == .application(name: "Arc"))
    }

    @Test func directOpenParserTreatsGoogleAsWebsite() async throws {
        let openTarget = YavenOpenCommandResolver.openTarget(from: "open google")

        #expect(openTarget == .url(URL(string: "https://www.google.com")!, displayName: "Google"))
    }

    @Test func directOpenParserAcceptsDomainRequests() async throws {
        let openTarget = YavenOpenCommandResolver.openTarget(from: "go to google.com")

        #expect(openTarget == .url(URL(string: "https://google.com")!, displayName: "google.com"))
    }

    @Test func gatewayRoutesOpenCommandsWithoutScreenCapture() throws {
        let route = YavenGateway().route(command: "open Mail")

        #expect(route.intent == .directOpen)
        #expect(route.threadKind == .automation)
        #expect(route.requiresScreenCapture == false)
        #expect(route.openTarget == .application(name: "Mail"))
    }

    @Test func gatewayRoutesEmailCleanupToMailSkills() throws {
        let route = YavenGateway().route(command: "organise my emails")

        #expect(route.intent == .mailCleanup)
        #expect(route.threadKind == .cleanup)
        #expect(route.requiresScreenCapture == false)
    }

    @Test func gatewayPrefersMailCleanupOverOpenCommand() throws {
        let route = YavenGateway().route(command: "open Mail and clean up my inbox")

        #expect(route.intent == .mailCleanup)
        #expect(route.threadKind == .cleanup)
    }

    @Test func gatewayRoutesHubSpotUpdatesToCRM() throws {
        let route = YavenGateway().route(command: "update HubSpot with a note from this call")

        #expect(route.intent == .crmUpdate)
        #expect(route.threadKind == .crm)
        #expect(route.requiresScreenCapture)
    }

    @Test func gatewayPrefersCRMUpdateOverOpenCommand() throws {
        let route = YavenGateway().route(command: "open HubSpot and log a note from this call")

        #expect(route.intent == .crmUpdate)
        #expect(route.threadKind == .crm)
    }

    @Test func gatewayBlocksSensitiveActions() throws {
        let message = YavenGateway().blockedSensitiveActionMessage(for: "type my password into this field")

        #expect(message != nil)
    }

    @Test func cleanupPlanParserDecodesCategoryPayload() throws {
        let response = """
        {
          "categories": [
            {
              "category": "newsletters",
              "message_ids": ["101", "102"],
              "summary": "2 newsletters from 1 sender"
            },
            {
              "category": "needs_reply",
              "message_ids": ["201"],
              "summary": "1 email that looks like it needs you"
            }
          ]
        }
        """

        let plan = try YavenCleanupPlanParser.decodePlan(from: response, totalReviewed: 200)

        #expect(plan.totalReviewed == 200)
        #expect(plan.batches.count == 2)
        #expect(plan.batches[0].category == .newsletters)
        #expect(plan.batches[0].defaultAction == .archive)
        #expect(plan.batches[1].category == .needsReply)
        #expect(plan.batches[1].defaultAction == .surface)
    }

    @Test func proposeCleanupPlanSkillReturnsPlaceholder() throws {
        let result = try YavenSkillRegistry.shared.run(name: "propose_cleanup_plan", input: [:])
        #expect(result == "plan presented to user, awaiting approval.")
    }

    @Test func threadStorePersistsMessagesAndCheckpoints() throws {
        let store = try temporaryThreadStore()
        let thread = try store.createThread(kind: .automation, title: "Research accounts")

        let message = try store.appendMessage(
            threadID: thread.id,
            role: .user,
            text: "Research these accounts"
        )
        try store.appendCheckpoint(
            threadID: thread.id,
            stepIndex: 1,
            status: .running,
            state: ["phase": "started"]
        )

        let messages = try store.messages(threadID: thread.id)
        let checkpoint = try store.latestCheckpoint(threadID: thread.id)

        #expect(messages == [message])
        #expect(checkpoint?.stepIndex == 1)
        #expect(checkpoint?.status == .running)
    }

    @Test func approvalPersistsForThread() throws {
        let store = try temporaryThreadStore()
        let thread = try store.createThread(kind: .automation, title: "Approve task")
        let approval = YavenApprovalRequest(
            id: UUID(),
            threadID: thread.id,
            kind: .crmSkill,
            title: "Update HubSpot",
            summary: "Create note",
            payloadJSON: #"{"goal":"Update HubSpot","summary":"Create note","actions":[]}"#,
            status: .pending,
            createdAt: Date(),
            resolvedAt: nil
        )

        try store.saveApproval(approval)

        #expect(try store.pendingApproval(threadID: thread.id) == approval)
    }

    @Test @MainActor func activityObserverDoesNotWriteBeforeOptIn() throws {
        let store = try temporaryThreadStore()
        let observer = YavenActivityObserver(store: store)
        observer.setEnabled(false)

        observer.recordActivityEventForTesting(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            windowTitle: "Inbox"
        )

        #expect(try store.activityEvents().isEmpty)
    }

    @Test @MainActor func uiActionRunnerSerializesDesktopControlWork() async throws {
        let store = try temporaryThreadStore()
        let runner = YavenTaskRunner(store: store)
        let firstThread = try store.createThread(kind: .automation, title: "First")
        let secondThread = try store.createThread(kind: .automation, title: "Second")
        var events: [String] = []

        async let first = runner.runUIAction(threadID: firstThread.id) {
            events.append("first-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            events.append("first-end")
            return .success()
        }
        async let second = runner.runUIAction(threadID: secondThread.id) {
            events.append("second-start")
            events.append("second-end")
            return .success()
        }

        _ = await [first, second]

        #expect(events == ["first-start", "first-end", "second-start", "second-end"])
    }

    @Test func hubSpotWriteSkillsRequireApprovalMetadata() throws {
        let skills = HubSpotSkills.makeAll()
        let createNote = try #require(skills.first { $0.name == "hubspot_create_note" })
        let updateDeal = try #require(skills.first { $0.name == "hubspot_update_deal_stage" })

        #expect(createNote.kind.requiresApproval)
        #expect(createNote.risk == .medium)
        #expect(updateDeal.kind.requiresApproval)
        #expect(updateDeal.risk == .high)
    }

    @Test func hubSpotSearchUsesConfiguredTokenAndMockedResponse() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHubSpotURLProtocol.self]
        let session = URLSession(configuration: config)
        MockHubSpotURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.url?.path == "/crm/v3/objects/contacts/search")
            let data = #"{"results":[{"id":"123"}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
        let client = HubSpotAPIClient(
            baseURL: URL(string: "https://mock.hubspot.test")!,
            session: session,
            accessTokenProvider: { "test-token" }
        )
        let skill = try #require(HubSpotSkills.makeAll(client: client).first { $0.name == "hubspot_search_records" })

        let result = try skill.run([
            "objectType": "contacts",
            "query": "Jane",
            "limit": 5
        ])

        #expect(result.contains(#""id":"123""#))
    }

    private func temporaryThreadStore() throws -> YavenThreadStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YavenTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("yaven.sqlite")
        return try YavenThreadStore(databaseURL: url)
    }
}

final class MockHubSpotURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler?(request) ?? {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
