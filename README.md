# Yaven

Yaven is a macOS menu-bar app for typed, screen-aware chat. It lives in the status bar, opens a custom floating panel, captures screenshots with ScreenCaptureKit when you send a message, and streams Claude responses through a Cloudflare Worker proxy.

Phase 0 is intentionally stripped down: no microphone, no transcription, no text-to-speech, no cursor overlay, and no pointing behavior.

## Prerequisites

- macOS 14.2+
- Xcode 15+
- Node.js 18+
- A Cloudflare account
- An Anthropic API key for Claude

## Worker Setup

The Worker keeps API keys out of the app bundle.

```bash
cd worker
npm install
```

For local development, create `worker/.dev.vars`:

```bash
ANTHROPIC_API_KEY=sk-ant-...
```

Then start the Worker:

```bash
npm run dev
```

The app currently points at `http://localhost:8787` in `CompanionManager.swift`.

To deploy the Worker:

```bash
cd worker
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler deploy
```

## App Setup

```bash
open leanring-buddy.xcodeproj
```

In Xcode:

1. Select the `leanring-buddy` scheme.
2. Set your signing team under Signing & Capabilities.
3. Press `Cmd+R` to build and run.

The app appears in the macOS menu bar, not the Dock.

## Permissions

Yaven needs:

- Screen Recording, so screenshots can be included as chat context.
- Screen Content, so ScreenCaptureKit can capture visible display content.

Yaven does not request microphone or speech recognition permissions.

## Project Structure

```text
leanring-buddy/
  leanring_buddyApp.swift        # Menu-bar app entry point
  MenuBarPanelManager.swift      # NSStatusItem and custom NSPanel lifecycle
  CompanionPanelView.swift       # SwiftUI panel UI
  CompanionManager.swift         # Typed chat, permissions, screenshots, Claude streaming
  ClaudeAPI.swift                # Claude streaming client
  CompanionScreenCaptureUtility.swift
  DesignSystem.swift
worker/
  src/index.ts                   # Cloudflare Worker proxy
docs/
  phase-0-audit.md               # Phase 0 removal audit
```

## Attribution

This fork is based on `farzaa/clicky`, which was released under the MIT License. See `ATTRIBUTION.md` and `LICENSE`.
