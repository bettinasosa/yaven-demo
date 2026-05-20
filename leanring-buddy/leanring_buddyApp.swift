//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar-only companion app. No dock icon, no main window — just an
//  always-available Yaven shell in the macOS menu bar and on screen.
//

import ServiceManagement
import SwiftUI
import Sparkle

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The app lives entirely in the menu bar panel managed by the AppDelegate.
        // This empty Settings scene satisfies SwiftUI's requirement for at least
        // one scene but is never shown (LSUIElement=true removes the app menu).
        Settings {
            EmptyView()
        }
    }
}

/// Manages the app lifecycle and starts the Phase 2 shell on launch.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private let shellController = YavenShellController()
    private let profileMemoryManager = ProfileMemoryManager()
    private let activityObserver = YavenActivityObserver.shared
    private lazy var onboardingManager = OnboardingManager(profileMemoryManager: profileMemoryManager)
    private var onboardingWindowController: OnboardingWindowController?
    private var sparkleUpdaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Yaven: Starting...")
        print("Yaven: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        OnboardingDS.Fonts.register()

        #if DEBUG
        Self.resetStateForDebug()
        #endif

        ClickyAnalytics.configure()
        ClickyAnalytics.trackAppOpened()

        menuBarPanelManager = MenuBarPanelManager(shellController: shellController)
        activityObserver.startIfEnabled()

        if onboardingManager.stage == .complete {
            // Returning user — start the shell immediately.
            shellController.start()
            startCalendarPoller()
        } else {
            // New user — show onboarding; shell starts when it completes.
            let controller = OnboardingWindowController(
                onboardingManager: onboardingManager,
                arrivalCoordinator: shellController.arrivalCoordinator,
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.shellController.start()
                    self.shellController.startFirstRunExperienceIfNeeded(
                        clickOrigin: self.onboardingManager.arrivalClickOrigin,
                        appearance: self.onboardingManager.selectedAppearance
                    )
                    self.startCalendarPoller()
                }
            )
            onboardingWindowController = controller
            controller.show()
        }

        registerAsLoginItemIfNeeded()
        // startSparkleUpdater()

        // #if DEBUG
        // runMemoryLayerSmokeTest()
        // #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        CalendarPoller.shared.stop()
    }

    private func startCalendarPoller() {
        CalendarPoller.shared.onUpcomingEvent = { event in
            PreCallBriefController.shared.generateBrief(for: event)
        }
        CalendarPoller.shared.start()
    }

    #if DEBUG
    /// Wipes all persisted state so every debug rebuild starts from a clean slate.
    private static func resetStateForDebug() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: "pendingFirstRunArrival")
        UserDefaults(suiteName: "com.humansongs.clicky")?.set(false, forKey: "hasCompletedOnboarding")

        for key in ["yavenUserRole", "yavenUserToolKeys", "yavenEntityId",
                    "yavenUserFirstName", "selectedYavenAppearance", "connectedToolKeys"] {
            defaults.removeObject(forKey: key)
        }

        // Wipe the SQLite thread store so the panel has no history.
        if let dbURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Yaven/yaven.sqlite") {
            try? FileManager.default.removeItem(at: dbURL)
        }

        print("Yaven DEBUG: State reset — fresh onboarding on this launch.")
    }

    private func runMemoryLayerSmokeTest() {
        // Step 1: bootstrap a profile from fake onboarding data (no Claude call).
        let fakeProfile = UserProfile(
            name: "Nick Price",
            email: "nick@yaven.ai",
            workContext: .company,
            company: "Yaven",
            role: "Founder",
            tools: [
                Tool(name: "HubSpot", composioKey: "hubspot"),
                Tool(name: "LinkedIn", composioKey: "linkedin"),
            ],
            automations: ["Draft outreach emails", "Log call summaries to HubSpot"]
        )
        profileMemoryManager.initializeFromOnboardingProfile(fakeProfile)
        print("Yaven DEBUG: Profile written to \(YavenStorage.profileURL.path)")
        print("Yaven DEBUG: Profile contents:\n\(YavenStorage.readProfileText() ?? "(empty)")")

        // Step 2: write two fake signals, then let the debounce fire (~30s) and rewrite.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s — let app settle
            let signal1 = Signal(
                timestamp: Date(),
                type: .messageDraft,
                action: .accepted,
                yavenOutput: "Hi Sarah, just following up on our conversation last week.",
                finalOutput: "Hi Sarah, just following up on our conversation last week.",
                context: "LinkedIn outreach to a prospect in fintech"
            )
            let signal2 = Signal(
                timestamp: Date(),
                type: .messageDraft,
                action: .edited,
                yavenOutput: "Hope you're well! Wanted to reconnect.",
                finalOutput: "Quick one — still interested in automating your outbound?",
                context: "Cold email follow-up"
            )
            profileMemoryManager.recordSignal(signal1)
            profileMemoryManager.recordSignal(signal2)
            print("Yaven DEBUG: 2 signals written. Profile rewrite fires in ~30s.")
            print("Yaven DEBUG: Signals log: \(YavenStorage.signalsLogURL.path)")
        }
    }
    #endif

    /// Registers the app as a login item so it launches automatically on
    /// startup. Uses SMAppService which shows the app in System Settings >
    /// General > Login Items, letting the user toggle it off if they want.
    private func registerAsLoginItemIfNeeded() {
        let loginItemService = SMAppService.mainApp
        if loginItemService.status != .enabled {
            do {
                try loginItemService.register()
                print("Yaven: Registered as login item")
            } catch {
                print("Yaven: Failed to register as login item: \(error)")
            }
        }
    }

    private func startSparkleUpdater() {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.sparkleUpdaterController = updaterController

        do {
            try updaterController.updater.start()
        } catch {
            print("Yaven: Sparkle updater failed to start: \(error)")
        }
    }
}
