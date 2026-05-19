# Onboarding Backend Notes

Date: 2026-05-16

## What Was Built

Three-stage onboarding backend. All logic lives in `OnboardingManager`; Betts builds views against it.

### New Files

| File | Purpose |
|------|---------|
| `UserProfile.swift` | All shared data models: `GoogleProfile`, `ConversationMessage`, `UserProfile`, `ConnectorType`, `ConnectorStatus`, `OnboardingConnectorState` |
| `GoogleAuthClient.swift` | Google OAuth via `ASWebAuthenticationSession` with PKCE (RFC 8252). No client secret. |
| `ProfileInterviewSession.swift` | Claude conversation that extracts a structured `UserProfile` from a natural chat. |
| `OnboardingManager.swift` | Central `ObservableObject` driving all three stages. Betts observes this. |

### Modified Files

| File | Change |
|------|--------|
| `leanring_buddyApp.swift` | Added `OnboardingManager` instance in `CompanionAppDelegate` |
| `CompanionPanelView.swift` | Added `#if DEBUG` reset button in footer (see below) |

## OnboardingManager API

`OnboardingManager` is the only object Betts needs to know about.

### Stages

```
.googleSignIn → .conversation → .connectors → .complete
```

### Published State

```swift
var stage: Stage                              // current stage
var isSigningInWithGoogle: Bool
var googleSignInErrorMessage: String?
var googleProfile: GoogleProfile?             // set after Stage 1
var conversationMessages: [ConversationMessage] // Stage 2 chat history (drive a message list)
var isStreamingResponse: Bool                 // true while Claude is typing
var connectors: [OnboardingConnectorState]    // Stage 3 connector list
var userProfile: UserProfile?                 // final output, populated when Stage 2 completes
static let privacyNotice: String              // "Yaven does not share or sell your data."
```

### Actions

```swift
func startGoogleSignIn()                      // Stage 1 — call from sign-in button
func sendConversationMessage(_ text: String)  // Stage 2 — call on text submit
func connectGmail()                           // Stage 3 — placeholder, Composio TODO
func skipConnectors()                         // Stage 3 — skips remaining, completes onboarding
func proceedFromConnectors()                  // Stage 3 — proceeds with current connection states
```

### ConversationMessage

```swift
struct ConversationMessage: Identifiable {
    let id: UUID
    let role: Role          // .user or .assistant
    var content: String     // assistant messages update in-place while streaming
}
```

A streaming assistant message starts as `content: ""` and grows as chunks arrive. The last
message is always the one being updated. Build the list view against this — it handles
the typing cursor naturally.

### ConnectorType

```swift
enum ConnectorType: CaseIterable {
    case gmail, hubspot, linkedin, lusha
    var displayName: String { ... }
}
```

`OnboardingConnectorState.isSuggested` is derived from the extracted `UserProfile` — show
suggested connectors first or with a badge.

## Debug Reset

`#if DEBUG` only. A small "Reset Onboarding" button sits at the trailing end of the
`CompanionPanelView` footer (10pt, dimmed). Tapping it calls
`onboardingManager.resetOnboardingForTesting()`, which resets all state to `.googleSignIn`
and clears `UserDefaults`, so you can cycle through onboarding repeatedly without Terminal.

`CompanionPanelView` is not instantiated at runtime in Phase 1 (it's a Phase 0 file).
When Betts builds the actual onboarding views against `YavenPanelView`, the reset
trigger should move there.

## Google OAuth Prerequisite

The OAuth client in Google Cloud Console **must be type "iOS"** (not "Web"). The iOS type
allows the reverse-client-ID redirect scheme (`com.googleusercontent.apps.<client-id>`)
without registering a URL scheme in `Info.plist`. Using type "Web" will break the PKCE flow.

## What's Not Done Yet

- **Storage**: `UserProfile` is Codable and ready, but nothing writes it to disk yet.
  Next: `~/Library/Application Support/Yaven/user-profile.json`.
- **Composio connectors**: `connectGmail()` is a stub. Wire Composio OAuth through the
  Cloudflare Worker when connectors work begins.
- **UI wiring into `YavenPanelView`**: `OnboardingManager` is instantiated in the app
  delegate but not yet passed to `YavenShellController` or `YavenPanelView`. Phase 2
  task — Betts drives this.
- **Production Worker URL**: Currently hardcoded to `http://localhost:8787` in `ClaudeAPI.swift`.
