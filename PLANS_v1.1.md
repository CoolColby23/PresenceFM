# PresenceFM — v1.1 Plans

This file captures the prioritized plans and implementation steps for v1.1. It mirrors the TODOs tracked in the task list so plans are available locally in the repository.

## High-level goals
- Release v1.1.0 with preview builds enabled and packaging verification.
- Improve reliability of scrobbling and persistence.
- Polish UI/UX and accessibility for the dashboard and menu bar.
- Prepare groundwork for optional privacy-first cloud sync.

## Prioritized Features (v1.1)
1. Preview CI builds and artifact uploads (implemented: `.github/workflows/preview-build.yml`).
2. Packaging verification and DMG artifact checks in CI.
3. Improve scrobble retry/backoff and idempotency in `ScrobbleQueue`.
4. Expand Widget/App Intents coverage and Shortcuts actions.
5. Add basic opt-in encrypted settings sync (design, not shipped server).

## UI / UX improvements
- Create a small design system (spacing, type scale, color tokens) in `brand/`.
- Refresh dashboard card hierarchy: highlight Now Playing, next Actions, then Insights.
- Add compact list mode and improved 7-day activity chart visuals.
- Accessibility audit: VoiceOver labels, keyboard shortcuts, focus rings, and contrast.

## Backend / Persistence improvements
- Make SwiftData migrations transactional with rollback backups.
- Persist scrobble queue to disk atomically and ensure idempotent delivery.
- Add structured diagnostics and bounded logs for long-running sessions.
- Reduce polling frequency where appropriate and reuse artwork cache across sessions.

## Implementation Steps (short-term)
1. Create `preview/v1.1` branch and open PR against `main`.
2. Extend preview workflow to upload signed preview artifacts or publish to a draft release.
3. Implement improved retry/backoff in `Sources/ScrobbleQueue.swift` and add unit tests.
4. Scaffold a design-system module and update `Sources/Views.swift` incrementally.
5. Run an accessibility pass and update `Documentation/ARCHITECTURE.md` with migration notes.

## Commands
Create a branch and push preview changes:
```bash
git checkout -b preview/v1.1
git add .
git commit -m "chore: add v1.1 plans and preview CI"
git push --set-upstream origin preview/v1.1
```

## Notes
- This file is intentionally implementation-focused — each section can be expanded into dedicated issues or PRs.

---
Generated: 2026-08-07
