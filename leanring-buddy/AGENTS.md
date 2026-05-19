# leanring-buddy Target Notes

Use the root `AGENTS.md` for project-wide instructions.

This directory contains the macOS app target source. Runtime behavior is now the Yaven shell plus Activity Inbox:

- no app-side speech features
- no cursor overlay
- no element pointing
- no tutor persona
- screen capture only on submit
- durable task/thread state in the local SQLite store
- approval-first execution for risky desktop and CRM writes
- panel close must not cancel background task threads

Keep internal target and folder names unchanged unless the user explicitly asks for a rename.
