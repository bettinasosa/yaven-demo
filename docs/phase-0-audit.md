# Phase 0 Audit

Date: 2026-05-16

Phase 0 is a strip-down pass for the fork of `farzaa/clicky`. It should remove Clicky voice, cursor, pointing, and tutor-specific surfaces without adding new Yaven product features.

## Constraints

- Remove voice entirely, not behind a feature flag.
- Remove microphone permission prompts, transcription providers, push-to-talk handling, and text-to-speech playback.
- Remove cursor overlay and element pointing entirely.
- Remove teaching/tutor persona and Clicky-specific user-visible copy.
- Change user-visible app name to `Yaven`.
- Keep internal Clicky-era class, file, and folder names for now unless deleting a removed feature file.
- Keep the Cloudflare Worker, Claude streaming client, ScreenCaptureKit utility, and menu-bar `NSPanel` infrastructure untouched.
- Preserve the MIT license and add `ATTRIBUTION.md`.
- The app must build and launch after each implementation task. Repo instructions also say not to run `xcodebuild` from the terminal because it can invalidate TCC permissions, so build sanity should be done through Xcode unless that instruction changes.

## Current Architecture Snapshot

- App target is a macOS menu-bar-only app (`LSUIElement = YES`) using SwiftUI plus AppKit bridging.
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` for `leanring-buddy`, so adding or deleting Swift files in that directory changes target membership automatically.
- `MenuBarPanelManager.swift` owns the `NSStatusItem` and borderless menu-bar `NSPanel`. This is infrastructure to keep.
- `CompanionPanelView.swift` is the only main user-facing UI surface after overlay removal. It already contains some `Yaven` text and a typed chat composer.
- `CompanionManager.swift` is the central state object. It still owns voice state, dictation, shortcut monitoring, overlay management, onboarding overlay/video flow, point parsing, and Claude screenshot chat.
- `ClaudeAPI.swift` provides the streaming Claude client. Keep untouched.
- `CompanionScreenCaptureUtility.swift` provides ScreenCaptureKit multi-monitor screenshots. Keep untouched.
- `worker/src/index.ts` still exposes `/chat`, `/tts`, and `/transcribe-token`. Keep untouched in Phase 0 even though app voice code should stop using `/tts` and `/transcribe-token`.

## Keep Untouched

- `worker/src/index.ts`
- `worker/package.json`
- `worker/wrangler.toml`
- `leanring-buddy/ClaudeAPI.swift`
- `leanring-buddy/CompanionScreenCaptureUtility.swift`
- `leanring-buddy/MenuBarPanelManager.swift` behavior and panel lifecycle
- Screen recording and screen content permission support in `WindowPositionManager.swift` and `CompanionManager.swift`, because typed Claude screenshot chat still needs screenshots.

`MenuBarPanelManager.swift` has Clicky-era internal names and comments. Those can stay unless they become user-visible.

## Voice Removal Surface

Delete or fully detach these app-side voice files:

- `BuddyDictationManager.swift`
- `BuddyTranscriptionProvider.swift`
- `AssemblyAIStreamingTranscriptionProvider.swift`
- `OpenAIAudioTranscriptionProvider.swift`
- `AppleSpeechTranscriptionProvider.swift`
- `BuddyAudioConversionSupport.swift`
- `GlobalPushToTalkShortcutMonitor.swift`
- `ElevenLabsTTSClient.swift`

Remove references from `CompanionManager.swift`:

- `CompanionVoiceState.listening/responding` if no longer needed for text-only chat.
- `lastTranscript` if only used for voice history naming.
- `currentAudioPowerLevel`
- `hasMicrophonePermission`
- `buddyDictationManager`
- `globalPushToTalkShortcutMonitor`
- `elevenLabsTTSClient`
- `shortcutTransitionCancellable`
- `voiceStateCancellable`
- `audioPowerCancellable`
- `pendingKeyboardShortcutStartTask`
- microphone polling and prompt helpers
- `bindVoiceStateObservation()`
- `bindAudioPowerLevel()`
- `bindShortcutTransitions()`
- `handleShortcutTransition(_:)`
- TTS fallback and TTS wait logic in transient hide scheduling

Remove references from `CompanionPanelView.swift`:

- `import AVFoundation` if only used for microphone permission.
- `microphonePermissionRow`
- `speechToTextProviderRow`
- status text/states for `Listening` and voice-oriented `Responding`
- disabled-send conditions tied to voice response state if replaced by a text-only processing state.
- hotkey copy that implies push-to-talk or voice.

Remove voice permission/configuration:

- `Info.plist` key `VoiceTranscriptionProvider`.
- Build settings `INFOPLIST_KEY_NSMicrophoneUsageDescription`.
- Build settings `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`.
- Any microphone permission copy in generated Info.plist settings or panel copy.

Keep Worker voice routes untouched per Phase 0 rules, but app code must not call them.

## Overlay And Pointing Removal Surface

Delete or fully detach these overlay/pointing files:

- `OverlayWindow.swift`
- `CompanionResponseOverlay.swift`
- `ElementLocationDetector.swift`

Remove references from `CompanionManager.swift`:

- `overlayWindowManager`
- `isOverlayVisible`
- `isClickyCursorEnabled`
- `setClickyCursorEnabled(_:)`
- `transientHideTask`
- `detectedElementScreenLocation`
- `detectedElementDisplayFrame`
- `detectedElementBubbleText`
- `clearDetectedElementLocation()`
- `PointingParseResult`
- `parsePointingCoordinates(from:)`
- point-tag handling in the Claude response pipeline.
- onboarding video, onboarding prompt bubble, onboarding music, and onboarding demo interaction if they depend on the removed overlay.
- `triggerOnboarding()` and `replayOnboarding()` should be removed or reduced to non-overlay setup if the UI still needs an onboarding completion action.

Remove references from `CompanionPanelView.swift`:

- hidden `showClickyCursorToggleRow`
- checks against `companionManager.isOverlayVisible`
- copy like `Show Yaven`, `Watch Onboarding Again`, and overlay-dependent start/onboarding controls.

Remove references from `DesignSystem.swift` only when they are exclusively for overlay visuals:

- `overlayCursorBlue`
- `BuddyComposerVisualStyle` if it is not used after removal.

Do not remove generic pointer cursor helpers from `DesignSystem.swift`; those are normal UI hover affordances for the menu panel.

## Teaching, Tutor, And Clicky Copy Surface

Remove or rewrite user-visible Clicky/tutor copy in:

- `README.md`
- root `AGENTS.md`
- `leanring-buddy/Info.plist`
- `leanring-buddy.xcodeproj/project.pbxproj` generated Info.plist keys
- `appcast.xml` if it remains part of visible update metadata
- panel copy in `CompanionPanelView.swift`
- AI system prompts in `CompanionManager.swift`

Current high-priority prompt removals:

- `companionVoiceResponseSystemPrompt` currently says "you're clicky", mentions push-to-talk, text-to-speech, and `[POINT:...]`.
- `onboardingDemoSystemPrompt` currently says "you're clicky, a small blue cursor buddy" and exists solely for pointing.

Use a neutral text-chat prompt for the remaining Claude screenshot flow. Do not add Yaven-specific product behavior in Phase 0.

Internal names that can stay for now:

- `CompanionManager`
- `CompanionPanelView`
- `ClickyAnalytics`
- `clickyDismissPanel`
- `leanring-buddy` folder, target, scheme, and module names

## User-Visible Yaven Rename Surface

Change user-visible app naming:

- `INFOPLIST_KEY_CFBundleDisplayName = Yaven`
- `INFOPLIST_KEY_CFBundleName = Yaven`
- `PRODUCT_NAME = Yaven` so the built app bundle is user-visible as `Yaven.app`.
- Product file reference currently points to `Clicky.app`; update if required by Xcode after changing `PRODUCT_NAME`.
- `Info.plist` screen capture usage string should say `Yaven`.
- Panel title and quit text already say `Yaven`, but remaining setup and hotkey copy still need cleanup.
- Logs may still say `Clicky`; these are not user-facing but should be cleaned if touched during the relevant file edits.

Do not rename:

- `leanring-buddy` directory
- `leanring-buddy` target/scheme
- Swift class/file names that survive Phase 0
- Bundle identifier, unless a later release/signing task explicitly requires it

## Attribution And License

- Preserve `LICENSE` as MIT.
- Add `ATTRIBUTION.md` with the original project, upstream repository, MIT license notice, and a short note that this fork is being adapted into Yaven.
- Do not remove Farza attribution from the license.

## Build Sanity Plan

- Do not use terminal `xcodebuild` under current repo instructions.
- After each implementation slice, open `leanring-buddy.xcodeproj` in Xcode and build/run the `leanring-buddy` scheme with `Cmd+R`.
- The app should launch as a menu-bar item, not a Dock app.
- Smoke-check the panel opens, does not request microphone or speech recognition, and no cursor overlay appears.
- For Worker sanity, `wrangler dev` can still validate `/chat`, but Worker code should remain unchanged during Phase 0.

## Suggested Implementation Order

1. Voice removal:
   - Simplify `CompanionManager` to typed-message processing only.
   - Remove microphone/speech permissions and voice files.
   - Simplify `CompanionPanelView` to screen permissions plus text chat.

2. Overlay removal:
   - Remove overlay manager usage, point parsing, onboarding overlay/video/demo code, and overlay files.
   - Keep ScreenCaptureKit screenshot capture for Claude context.

3. Teaching/Clicky copy removal:
   - Replace prompt and UI/docs copy with neutral Yaven wording.
   - Keep typed screenshot chat generic.

4. Yaven rename:
   - Update user-visible Info.plist/project product naming.
   - Add `ATTRIBUTION.md`.

5. Build sanity:
   - Build and launch in Xcode.
   - Search for disallowed app-side terms and APIs: microphone, speech recognition, push-to-talk, TTS, ElevenLabs app client, overlay, `[POINT:]`, and user-visible Clicky.
