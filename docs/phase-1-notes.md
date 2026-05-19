# Phase 1 Notes

Date: 2026-05-16

## Confirmed Working

- The app builds through Xcode and launches as `Yaven`.
- A 40x40 spherical glass orb appears at the bottom-right of the primary screen.
- The orb and panel use `NSVisualEffectView` with `.hudWindow` material and `.behindWindow` blending.
- The orb and panel are non-activating `NSPanel` windows at `.statusBar` level with all-spaces/fullscreen collection behavior.
- Clicking the orb opens a 460x320 glass command panel above it, right-aligned with the orb.
- `Space+Y` toggles the panel through AppKit local/global key monitors after macOS grants Accessibility access.
- Clicking outside the panel dismisses it while leaving the orb visible.
- The menu-bar item remains as a fallback summon, with right-click exposing `Quit Yaven`.
- Submitting text prints `Yaven command submitted: <command>` to the console and clears the input.

## Known Visual Quirks

- The panel is intentionally sparse: a question prompt, compact text input, and an empty content area below for Phase 2.
- Glass appearance is delegated to macOS materials, so contrast varies slightly by wallpaper and light/dark mode.
- The menu-bar item uses text (`Yaven`) rather than a custom template icon in Phase 1.
- Space+Y is a non-standard global chord. Because Space is not a real modifier key, other apps can still receive the Space key before Yaven sees the full chord; local Yaven input suppresses the Y key once the chord fires.

## Phase 2 Technical Debt

- Panel height is fixed at 460x320; Phase 2 will need dynamic sizing for cards and workflow states.
- Phase 0 Claude/screenshot files still compile but are not instantiated by the Phase 1 app runtime.
- The command submit handler is debug-only and should become the Phase 2 workflow entrypoint.
- No settings UI exists for rebinding the summon hotkey; the default is hardcoded to `Space+Y`.
