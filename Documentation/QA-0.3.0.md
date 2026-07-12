# PresenceFM 0.3.0 QA Record

Date: 2026-07-12

Build: 0.3.0 (3), locally packaged unsigned build

Environment: macOS 27.0 (26A5378j), Apple silicon

This record contains no credentials, user paths, or listening metadata. It supplements, rather than replaces, the complete release checklist in `MANUAL-QA.md`.

## Passed

- `swift test`: 26 tests passed across playback sessions, persistence and queue, artwork, listening insights, preferences and notifications, and security.
- Release build: `swift build -c release` completed successfully.
- Packaging: `scripts/package-app.sh` produced a launchable app with bundle version 0.3.0 (3), minimum macOS 15.0, the expected Apple Events usage description, and the bundled Discord application ID.
- Dashboard: the packaged app launched, reported Apple Music connected, and displayed the idle now-playing state without a crash.
- Listening History: totals, listening time, skipped count, artist count, top artists, seven-day chart accessibility, and populated activity rendered.
- Listening History search: filtering by artist updated the totals, chart, artist ranking, and visible activity consistently; clearing search restored the full result set.
- Queue: queued and retrying records rendered with redacted, actionable service messages; no retry or deletion was triggered during QA.
- Settings: general, retention, Discord, Last.fm, and advanced sections rendered; secure fields remained masked.
- Diagnostics: version and recovery controls rendered, and no credential or user-path content appeared in the visible redacted-log area.
- Website: the local dependency-free site loaded in Safari with working semantic navigation, headings, feature content, local brand assets, privacy links, and download links.
- Repository hygiene: `git diff --check` passed.

## Not exercised in this environment

- Clean-install Gatekeeper flow and Automation permission denial/recovery. The tested machine already had app state and permissions.
- Live playback transitions, seeking, artwork changes, local files, radio, and scrobble-threshold timing.
- Discord publishing, reconnect behavior, presence clearing, and timed Private Mode across sleep/wake.
- Last.fm authorization, now-playing submission, exactly-once scrobbling, offline recovery, revoked sessions, or manual queue retry/removal. Existing queue entries were deliberately left untouched.
- Notification authorization and notification deep links.
- CSV export, retention pruning, and clear-history confirmation. These could create files or delete existing local history.
- Upgrade migration from a preserved 0.2 data fixture.
- Launch-at-login mutation and behavior on macOS 15 through 26.
- Developer ID signing and Apple notarization. CI secrets and an Apple Developer identity are required.

These items must pass before the draft GitHub release is published publicly. Tag creation should wait until the account-dependent checks are complete or are explicitly accepted as release risk.
