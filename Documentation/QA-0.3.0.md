# PresenceFM 0.3.0 QA Record

Date: 2026-07-12

Build: 0.3.0 (3), locally packaged ad-hoc signed build

Environment: macOS 27.0 (26A5378j), Apple silicon

This record contains no credentials, user paths, or listening metadata. It supplements, rather than replaces, the complete release checklist in `MANUAL-QA.md`.

## Passed

- `swift test`: 31 tests passed across playback sessions, persistence and queue, artwork, listening insights, preferences and notifications, and security.
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

## Playback and artwork regression pass

- Repeated live Apple Music track changes updated PresenceFM metadata within the first observation window (under two seconds including UI capture overhead).
- A previous track's cover is removed immediately at transition; the new cover appeared within approximately three seconds when Apple Music required the Apple-hosted catalog fallback.
- Discord changed to the new title, artist, album, and timer and exposed the large image as `Apple Music album artwork` on the profile activity card.
- Pause and Private Mode each cleared the Discord activity; resuming playback/private mode restored it.
- Last.fm displayed live now-playing metadata and accepted a qualified listen exactly once during the test session.
- Multiple package rebuilds and launches did not display a macOS password dialog. Last.fm credentials persisted in the owner-only local credentials file without Keychain ACL prompts.
- History period/outcome/search filters, no-match state, CSV export, cancel/confirm clear flow, and queue isolation passed. A database backup restored all history and queue data after the destructive test.
- Automated regression suite: 31 tests passed across seven suites after the latency, artwork, Discord, credential-storage, and queue-concurrency changes.

## Not exercised in this environment

- Clean-install Gatekeeper flow and Automation permission denial/recovery. The tested machine already had app state and permissions.
- Live playback transitions, seeking, artwork changes, local files, radio, and scrobble-threshold timing.
- Discord publishing, reconnect behavior, presence clearing, and timed Private Mode across sleep/wake.
- Last.fm authorization, now-playing submission, exactly-once scrobbling, offline recovery, revoked sessions, or manual queue retry/removal. Existing queue entries were deliberately left untouched.
- Notification authorization and notification deep links.
- CSV export, retention pruning, and clear-history confirmation. These could create files or delete existing local history.
- Upgrade migration from a preserved 0.2 data fixture.
- Launch-at-login mutation and behavior on macOS 15 through 26.
- Developer ID signing and Apple notarization. This release intentionally uses ad-hoc signing because the project does not have a paid Apple Developer account; the documented Gatekeeper first-launch step remains an accepted distribution risk.

These items must pass before the draft GitHub release is published publicly. Tag creation should wait until the account-dependent checks are complete or are explicitly accepted as release risk.
