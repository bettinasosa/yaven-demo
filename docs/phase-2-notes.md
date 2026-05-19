# Phase 2 Notes

Date: 2026-05-16

## Confirmed Working

- The app builds through Xcode after adding the Phase 2 operator types.
- The Yaven panel now routes submits through `YavenAgentController` instead of printing commands.
- The panel captures screen context on submit, then uses `ClaudeAPI` against `http://localhost:8787/chat`.
- Normal prompts stream screenshot-aware Claude responses into the panel.
- Action-like prompts request a strict JSON operator plan; simple open/send requests may execute directly, while riskier plans render an approval card before execution.
- Prior user/assistant turns now persist locally in `UserDefaults` and are sent back to Claude as short conversation history.
- Chat memory and onboarding completion migrate from legacy defaults domains when present.
- The panel renders a transcript instead of a single-response slot, the transcript scrolls, and the command input stays pinned at the bottom.
- Approval commands such as `yes`, `approve`, or `do it` execute the currently rendered plan instead of starting a fresh chat.
- Approved plans execute through `YavenAutomationExecutor` with Accessibility and CGEvent primitives.
- Closing the panel cancels active Claude/execution tasks and resets the panel.
- The orb now has a blue/cyan glass tint and pulses while Claude or execution is in flight.
- The operator panel is fixed at 460x420 so new messages never resize or lower the input area.
- Xcode build and launch were verified after the memory/action-routing update.

## Known Issues

- Claude operator planning depends on the local Worker running at `http://localhost:8787/chat`.
- Click steps rely on Claude returning screenshot-pixel coordinates; complex multi-display layouts may need calibration.
- `typeText` currently uses pasteboard paste under the hood for reliability, same as `pasteText`.
- Simple app-open commands use `NSWorkspace` directly before screenshot capture; richer actions still use the Claude operator plan path.
- Notifications are local-only and fire for approval/done/failure states when the notification permission is granted.
- Screen context is captured on submit only; there is no background watcher.
- Transcript memory is local to this Mac and capped to the latest 30 panel messages; there is no account-level sync yet.

## Deferred

- Provider-native Gmail/Calendar actions are not implemented in this slice.
- There is no settings UI for Worker URL, model, hotkey, recording mode, or action policies.
- The legacy Worker still contains unused TTS/transcription routes from upstream.
