# Yaven - Agent Instructions

<!-- This is the single source of truth for AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md -->

## Overview

Yaven is a macOS menu-bar app. It has no Dock icon. Returning users land in the Claude computer-operator shell; first-run users may see the centered onboarding window until onboarding is complete:

- a single expanding notch window anchored top-centre of the primary screen (in the menu bar area)
- collapsed: a 220 × 36 camera-width pill using the selected Black or Glass shell surface
- expanded: the pill becomes a full-width header and the widget panel drops below it (600 × variable height)
- open via hover (300 ms delay), pill click, menu-bar click, or `Space+Y`
- close via pill click, Escape, click outside, or hotkey
- on-submit screen context capture via ScreenCaptureKit
- screen-aware Claude chat through the local Cloudflare Worker at `http://localhost:8787/chat`
- local task/thread history persisted through SQLite and sent back to Claude as short conversation history
- an Activity Inbox in the panel for approvals, running work, and recent completed tasks
- optional local app/window activity logging after explicit opt-in; no continuous screen capture
- direct execution for simple open/send requests
- approval-first operator plans for riskier app switching, clicking, typing/pasting, waiting, and notifications
- approved execution through Accessibility and CGEvent primitives

Yaven captures screen context only when the user submits a request. It does not continuously watch or record screens in the background. If the user opts in, Yaven may log lightweight local app/window activity metadata for context. Simple open/send requests may execute directly; riskier or ambiguous UI automation plans require explicit approval.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`)
- **Framework**: SwiftUI with AppKit bridging for `NSStatusItem`, `NSPanel`, `NSVisualEffectView`, and SwiftUI Liquid Glass APIs when available
- **Shell Controller**: `YavenShellController` owns the orb window, fixed-height panel window, global hotkey, screen-change repositioning, dismissal monitors, and notification deep-link routing into task threads
- **Gateway**: `YavenGateway` is the in-app routing and policy kernel. It classifies commands into direct open, Mail cleanup, HubSpot CRM update, operator plan, or chat; it also owns sensitive-action blocks and operator-plan validation.
- **Agent Controller**: `YavenAgentController` owns Claude requests, screen context capture, durable thread state, approval plans, Activity Inbox state, and foreground selection. It should ask `YavenGateway` for routing and policy decisions instead of duplicating intent checks inline.
- **Task Runner**: `YavenTaskRunner` keeps task threads running after the panel closes, allows multiple non-UI tasks, and serializes desktop-control work through a single UI-action queue
- **Thread Store**: `YavenThreadStore` persists threads, messages, checkpoints, approvals, skill execution records, and activity events in SQLite at `~/Library/Application Support/Yaven/yaven.sqlite`
- **Activity Awareness**: `YavenActivityObserver` logs app switches and optional focused window titles only after explicit opt-in. It never captures screenshots, OCR, or AX trees continuously.
- **Onboarding**: `OnboardingManager` gates first-run setup and migrates the legacy Clicky completion flag so renamed installs do not re-run onboarding unnecessarily. Onboarding titles use bundled editorial serif fonts registered at launch. Phase 3 lets the user choose Black or Glass shell mode, then ends onboarding with a timed arrival transition, orb bloom, ceremonial first panel, and optional inbox cleanup.
- **First-value inbox cleanup**: `YavenCleanupController` lists recent Mail messages via AppleScript skills, asks Claude for a fixed five-category plan, executes archive/move actions after explicit approval, then surfaces needs-reply cards with draft handoff to the existing agent loop.
- **Skills**: `YavenSkillRegistry`, `MailSkills`, and `HubSpotSkills` provide Mail cleanup skills and approval-first HubSpot CRM read/write skills.
- **Windows**: one `YavenNotchWindow` (`.mainMenu+3` level) that resizes between a 220×36 camera-width pill and expanded panel states. `YavenPanelWindow` is kept compileable but not instantiated. `YavenNotchExpansion` (ObservableObject owned by the shell controller) is the shared open/close state — the view writes to it and the shell controller animates the window frame in response. The notch reads the persisted appearance and renders either the current solid black shell or a smoked native glass shell using SwiftUI `glassEffect` on macOS 26+ with material fallbacks.
- **Hotkey**: AppKit local/global `NSEvent` monitors for `Space+Y`; key monitoring depends on Accessibility access
- **Claude**: `ClaudeAPI.swift` streams screenshot-aware chat and decodes strict JSON operator plans through the Worker proxy
- **Automation**: `YavenAutomationExecutor` executes validated plans; simple open/send plans may run directly, while riskier plans pause for approval. It must never enter passwords, payment details, or system security prompts
- **Notifications**: `YavenNotificationManager` sends local approval/done/error notifications after user authorization and includes thread IDs so notifications reopen the right Activity Inbox item
- **Analytics**: PostHog via `ClickyAnalytics.swift`, currently only app-open level unless Phase 2 adds explicit shell events

### Preserved But Unused Phase 0 Surfaces

`CompanionManager.swift` and `CompanionPanelView.swift` remain compileable legacy typed-chat surfaces and are not instantiated at runtime. `CompanionScreenCaptureUtility.swift`, `WindowPositionManager.swift`, `ClaudeAPI.swift`, and `worker/` are now reused by the Phase 2 operator path.

The Worker still contains legacy `/tts` and `/transcribe-token` routes from the upstream project. Phase 2 app code must not reintroduce app-side speech, audio capture, cursor overlay, or pointing behavior.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~100 | Menu-bar app entry point. Creates `YavenShellController`, `MenuBarPanelManager`, activity observer, and first-run onboarding, then starts the shell for completed users. |
| `YavenShellController.swift` | ~431 | Shell coordinator. Owns the single notch window and `YavenNotchExpansion`. Wires expansion and drag-progress changes to window resizing. Manages collapsed positioning, hotkey, screen-change repositioning, click-outside monitors, and first-run flow. |
| `YavenAgentController.swift` | ~1196 | Agent state controller. Captures context, calls Claude, persists/migrates durable threads, manages Activity Inbox selection, approvals, direct commands, CRM plans, and execution handoff. Routing decisions come from `YavenGateway`. |
| `YavenGateway.swift` | ~240 | In-app gateway/policy kernel for intent routing, sensitive-action blocks, approval command parsing, auto-execution rules, and operator-plan validation. |
| `YavenTaskRunner.swift` | ~159 | Background task owner. Keeps threads alive after panel close, tracks active threads, and serializes desktop-control actions. |
| `YavenThreadModels.swift` | ~115 | Codable thread, message, checkpoint, approval, activity event, and skill execution record models. |
| `YavenThreadStore.swift` | ~515 | SQLite-backed durable store for threads, messages, checkpoints, approvals, activity events, skill execution records, and legacy chat migration. |
| `YavenSQLiteDatabase.swift` | ~155 | Small system-SQLite wrapper used by `YavenThreadStore`. |
| `YavenActivityObserver.swift` | ~153 | Opt-in app/window activity logger using `NSWorkspace.didActivateApplicationNotification` and AX window titles when already permitted. |
| `YavenOpenCommandResolver.swift` | ~271 | Parses simple open requests, resolves app names/aliases, and opens website-style targets without falling back to Claude planning. |
| `YavenAgentModels.swift` | ~204 | Agent state, chat transcript, computer context, action plan, action step, execution result, and strict plan parsing models. |
| `YavenAutomationExecutor.swift` | ~214 | Executes validated UI automation plans through Accessibility, CGEvent keyboard/mouse events, pasteboard, app launching, and notifications. |
| `YavenComputerContextProvider.swift` | ~70 | Builds frontmost-app/window and screen metadata for Claude from ScreenCaptureKit captures. |
| `YavenNotificationManager.swift` | ~73 | Local notification authorization, delivery, and thread deep-link wrapper. |
| `SpaceYHotkeyMonitor.swift` | ~109 | AppKit key monitors that toggle the shell when Space is held and Y is pressed. |
| `YavenNotchWindow.swift` | ~50 | `NSPanel` at `.mainMenu+3` level. `canBecomeKey = true` for text input. Handles Escape via `onEscapePressed` callback. |
| `YavenNotchView.swift` | ~638 | Unified expanding notch view. Defines `YavenNotchExpansion` (ObservableObject). Pill strip at top animates corner radii on expand; panel content fades in below. Hover (300 ms), tap, or drag-down opens. Renders the selected Black or smoked Glass shell surface with shine and approval cues. |
| `YavenOrbWindow.swift` | ~34 | Legacy orb panel — kept compileable but no longer instantiated. |
| `YavenOrbView.swift` | ~301 | Legacy orb view — kept compileable but no longer instantiated. Renders compatible Black and Glass orb bodies. |
| `YavenPanelWindow.swift` | ~44 | Non-activating key-capable `NSPanel` subclass for the command panel and Escape handling. |
| `YavenPanelView.swift` | ~840 | SwiftUI Activity Inbox and thread-detail panel with approval/running/recent sections, bottom-pinned prompt input, persisted transcript bubbles, approval cards, result/error states, permission shortcuts, and shared panel/widget focus requests. |
| `YavenWidgetBar.swift` | ~1371 | Dynamic widget panel inside the expanded notch. Handles compact dashboard, chat, agents, automations, approvals, and focus requests from shell cues. |
| `VisualEffectBackground.swift` | ~25 | `NSVisualEffectView` wrapper for native macOS glass material. |
| `MenuBarPanelManager.swift` | ~68 | `NSStatusItem` fallback summon and right-click quit menu. |
| `CompanionManager.swift` | ~206 | Preserved Phase 0 typed-chat state manager. Not instantiated by the Phase 2 runtime. |
| `CompanionPanelView.swift` | ~426 | Preserved Phase 0 typed-chat panel. Not instantiated by the Phase 2 runtime. |
| `CompanionScreenCaptureUtility.swift` | ~132 | ScreenCaptureKit utility used for on-submit multi-screen context capture. |
| `ClaudeAPI.swift` | ~396 | Claude streaming client, screen-aware chat wrapper, conversation-history forwarding, and strict operator-plan generation. |
| `ClickyAnalytics.swift` | ~55 | PostHog analytics wrapper. Internal name remains from upstream for now. |
| `Caprasimo-Regular.ttf` | ~resource | Bundled display serif inspired by the Café Binocle reference. |
| `Fraunces-VariableFont_opsz,wght.ttf` | ~resource | Bundled secondary serif retained for Yaven panel titles and future onboarding alternates. |
| `OnboardingDesignSystem.swift` | ~102 | Design tokens for onboarding: Pastel Dawn blue/pink/lavender/cream palette, registered editorial-serif typography, layout constants. |
| `YavenGradientBackground.swift` | ~150 | Animated flowing pastel cloud gradient via TimelineView + Canvas. |
| `OnboardingWindow.swift` | ~45 | NSWindow subclass (not NSPanel) for the centered onboarding surface. Becomes key for Google OAuth. |
| `OnboardingWindowController.swift` | ~65 | Owns the onboarding window; observes stage via Combine and fades out on .complete, then calls shellController.start(). |
| `OnboardingRootView.swift` | ~56 | Top-level SwiftUI container. Switches stage views with cross-fade over the animated gradient. |
| `OnboardingSignInView.swift` | ~86 | Stage 1 — display-serif wordmark, Google sign-in button, spinner, error message, privacy notice. |
| `OnboardingConversationView.swift` | ~267 | Stage 2 — pastel display-serif masthead over a live streaming chat list, message-level thinking bubble, floating glass input dock, send button. |
| `OnboardingConnectorsView.swift` | ~146 | Stage 3 — choose Yaven's shell appearance with cardless Dark/Light orb selectors. Filename remains connector-era for project stability. |
| `OnboardingLaunchAnimationView.swift` | ~79 | Legacy launch beat (superseded for new users by arrival transition). |
| `OnboardingArrivalCoordinator.swift` | ~95 | Timed arrival state machine: onboarding fade, dark wash, orb bloom, ceremonial panel summon. |
| `OnboardingArrivalTransitionView.swift` | ~25 | Onboarding-window fade + wash during `.arrivalTransition`. |
| `OnboardingArrivalOverlayWindow.swift` | ~95 | Fullscreen glow-ring overlay aligned to the shell orb during bloom. |
| `YavenCleanupModels.swift` | ~95 | Cleanup categories, plans, needs-reply items, first-run panel mode. |
| `YavenMailCleanupApproval.swift` | ~90 | Codable approval payload for general Mail cleanup requests routed through Mail skills. |
| `YavenCleanupController.swift` | ~230 | Inbox scan → Claude categorization → approval execution → done-state generation. |
| `YavenCleanupPlanParser.swift` | ~115 | Strict JSON parsing for cleanup plans and needs-reply card labels. |
| `GmailComposioClient.swift` | ~110 | Async Gmail client via Composio action execution API, proxied through the Worker `/composio-action`. |
| `MailAppleScriptRunner.swift` | ~210 | Legacy Mail.app AppleScript runner. Kept compileable but no longer called — replaced by GmailComposioClient. |
| `MailSkills.swift` | ~85 | Legacy Mail skill definitions. Kept compileable but no longer the active path — replaced by direct GmailComposioClient calls. |
| `HubSpotSkills.swift` | ~344 | Approval-first HubSpot CRM skill pack for search/read, note/task creation, deal stage updates, and email logging. |
| `HubSpotCRMPlan.swift` | ~25 | Codable approval-plan models for HubSpot CRM update proposals. |
| `YavenSkillRegistry.swift` | ~59 | Skill lookup, metadata, and execution dispatch across Mail and HubSpot skills. |
| `YavenFirstValueViews.swift` | ~280 | First message, scanning progress, categories card, execution, and done views. |
| `YavenOnboardingMascotView.swift` | ~172 | SwiftUI-only Black and Glass surface preview renderer used by onboarding and the arrival animation. |
| `OnboardingManager.swift` | ~380 | Central ObservableObject for onboarding stages, appearance persistence, launch animation transition, and legacy completion-state migration. |
| `UserProfile.swift` | ~159 | Shared data models: GoogleProfile, ConversationMessage, UserProfile, connector state, and onboarding appearance options. |
| `GoogleAuthClient.swift` | ~310 | Google OAuth via ASWebAuthenticationSession + PKCE, with guarded callback continuation handling. |
| `docs/onboarding-backend-notes.md` | ~111 | Nick's onboarding backend notes — API reference, what's done, what's next. |
| `docs/phase-0-audit.md` | ~212 | Phase 0 audit and removal plan. |
| `docs/phase-1-notes.md` | ~31 | Phase 1 shell verification notes and historical follow-ups. |
| `docs/phase-2-notes.md` | ~new | Phase 2 operator implementation notes, verification, and known issues. |

## Build & Run

```bash
open leanring-buddy.xcodeproj
```

Select the `leanring-buddy` scheme, set signing team, then use `Cmd+R` in Xcode.

Do **not** run `xcodebuild` from the terminal. It can invalidate TCC permissions and make the app re-request screen access.

## Code Style & Conventions

### Naming

- Be clear and specific with variable and method names.
- Optimize for clarity over concision.
- Avoid single-character variable names.
- Preserve original variable names when passing arguments unless a rename improves clarity across the call site.

### Code Clarity

- Clear is better than clever.
- Keep behavior easy to follow for a developer with no project context.
- Add comments only when a name cannot explain the intent or when AppKit bridging is non-obvious.

### Swift/SwiftUI

- Use SwiftUI for UI unless AppKit is required.
- Keep UI state updates on `@MainActor`.
- Bridge AppKit `NSPanel`/`NSWindow` into SwiftUI with `NSHostingView`.
- Use SwiftUI `glassEffect(_:in:)`, `Glass.interactive(_:)`, and `.buttonStyle(.glass(...))` for Yaven glass surfaces on macOS 26+; keep availability guards and fall back to `VisualEffectBackground`/materials for older deployment targets.
- For non-activating panels that need input, override `canBecomeKey` in the `NSPanel` subclass.
- Keep shell windows `.nonactivatingPanel`; the app must not become frontmost.
- Keep all agent UI state on `@MainActor`.
- Validate every Claude operator plan before rendering approval or execution.
- Route action-like user requests into direct execution or approval planning; answer normally only when the user is discussing, asking, or brainstorming.
- Auto-execute simple open/send requests, but keep destructive, ambiguous, or high-risk requests behind review.
- Treat explicit approval phrases in the command box, such as `yes`, `approve`, or `do it`, as approval for the current rendered plan.
- Panel close hides the UI but must not cancel durable background threads. Use explicit cancel actions to stop a thread.
- Multiple non-UI/background tasks may run concurrently. Desktop-control actions that click, type, switch apps, or use the pasteboard must go through the single UI-action queue.
- All buttons must show a pointer cursor on hover when applicable.

### Liquid Glass

- Treat Apple's Liquid Glass documentation as the source of truth:
  `https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views` and
  `https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass`.
- Prefer system-provided Liquid Glass from standard SwiftUI controls, toolbars, sheets, and popovers before building custom glass.
- Apply custom glass with `glassEffect(_:in:)`; choose a shape that matches the component instead of accepting the default capsule when it would look wrong.
- Apply appearance-affecting modifiers before `glassEffect(_:in:)`, because the effect captures the view content for rendering.
- Use `Glass.interactive(_:)` or `.buttonStyle(.glass(...))` for controls that should respond to touch or pointer interaction.
- Use tint sparingly to communicate prominence, not as a general color wash.
- Wrap groups of nearby custom glass elements in `GlassEffectContainer` so SwiftUI can render them efficiently and blend or morph their shapes correctly.
- Tune `GlassEffectContainer` spacing intentionally: overly large spacing can merge nearby glass at rest; aligned spacing supports deliberate morphing during movement.
- For glass elements that appear, disappear, or morph, assign stable `glassEffectID(_:in:)` values inside a namespace and use system `GlassEffectTransition` styles such as matched geometry or materialize.
- Limit the number of simultaneous custom glass effects and containers. Too many glass effects degrade rendering performance.
- When content should visually continue behind translucent sidebars or inspectors, prefer Apple's background extension and scroll-extension patterns over hand-built blur layers.

### Do Not

- Do not execute destructive, ambiguous, or high-risk UI automation before explicit user approval.
- Do not continuously capture screens, OCR, AX trees, or content in the background. Lightweight app/window activity logging is allowed only after explicit opt-in and must stay local.
- Do not enter passwords, passcodes, payment details, security codes, or system security prompts.
- Do not claim Claude has clicked, typed, sent, deleted, scheduled, or changed anything unless Yaven completed the direct command or `YavenAutomationExecutor` completed the plan.
- Do not reintroduce app-side speech, audio capture, cursor overlay, or pointing behavior.
- Do not rename the `leanring-buddy` project directory, target, or scheme.
- Do not run `xcodebuild` from the terminal.
- Do not modify the Cloudflare Worker unless the user explicitly asks.

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain why.
- Do not force-push to main.

## Self-Update Instructions

When changes affect this file, update it:

1. Add new source files to the Key Files table.
2. Remove deleted source files from the Key Files table.
3. Update architecture when patterns or major structure change.
4. Update build commands if the build process changes.
5. Add new conventions if the user establishes them.
6. Update approximate line counts when drift is significant.

Do not update this file for minor edits that do not affect architecture or conventions.
