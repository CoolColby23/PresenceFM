# PresenceFM 1.0.0 Release-Candidate QA

Updated: 2026-07-13

This is the release decision record for 1.0.0. A checked item has reproducible
evidence; an unchecked item is a release blocker unless the maintainer records
an explicit, user-visible accepted risk before publication.

## Automated and package gates

- [x] Debug `swift test` passes: 85 tests across 16 suites, including Discord customization, per-provider monitor reporting, and Apple Music Radio eligibility/queue transport. The earlier optimized Private Mode expiration check also passed 10 repeated runs.
- [x] Address Sanitizer and Thread Sanitizer test runs pass with no reported memory or data-race issue.
- [x] The release app builds, signs, and passes strict bundle verification as 1.0.0.
- [x] Pull-request CI uses pinned Xcode 26.0, tests Swift code with a coverage report, checks patch hygiene, verifies the website, packages the app, and verifies the DMG.
- [x] Tagged releases reject a tag that disagrees with `VERSION`, verify the website and DMG/checksum, then create a draft release with DMG and checksum artifacts.
- [x] Website metadata, fragments, local assets, sitemap, and robots file pass the dependency-free integrity check.
- [x] GitHub Pages deployment is defined for website changes on `main`.

## App interaction evidence

- [x] Dashboard sections render with live playback and integration status.
- [x] Command-1 through Command-5 navigate to the five dashboard destinations without opening duplicate windows.
- [x] Shift-Command-P enters Private Mode, updates the controls, and exits again without opening another window.
- [x] Last.fm disconnection presents consequences and can be canceled without changing the account.
- [x] Onboarding exposes its current step to accessibility and supports Return/Escape navigation.
- [ ] Complete a full keyboard and VoiceOver traversal of onboarding, settings, queue, history filters, diagnostics, and menu-bar controls.
- [ ] Verify increased contrast, reduced motion, and the supported macOS accessibility display settings.

## Website evidence

- [x] Desktop plus 390- and 320-pixel mobile layouts render without overflow, a blank page, or a framework overlay.
- [x] The mobile navigation opens, updates its accessible state, closes after selection, and closes with Escape.
- [x] Browser console inspection reports no relevant warnings or errors.
- [x] Download, source, privacy, support, changelog, and release-QA destinations are present and use durable public URLs.
- [ ] Confirm the production GitHub Pages URL after Pages is enabled in repository settings.
- [ ] Replace release-candidate language with final 1.0 release language only after this record is complete.

## Provider and integration blockers

- [ ] Apple Music: play, pause, seek, skip, quit, relaunch, permission denial/recovery, sleep/wake.
- [ ] Spotify: play, pause, seek, skip, quit, relaunch, provider switching, sleep/wake.
- [ ] YTMDesktop: authorization, rejection, play, pause, seek, skip, live-stream exclusion, reconnect.
- [ ] TIDAL: play, pause, seek, skip, quit, relaunch, sleep/wake on the documented best-effort metadata surface.
- [ ] Discord: offline startup, reconnect, restart, option refresh, pause/stop clearing, and Private Mode clearing.
- [ ] Last.fm: authorization, now-playing, exactly-once scrobble, offline queue, rate limit, revoked session, retry, and removal.

## Persistence, privacy, and compatibility blockers

- [ ] Clean install and upgrade from every supported public persistence version.
- [ ] Corrupt/partial store recovery and backup restore with preserved failed data.
- [ ] Timed Private Mode expiration across sleep and relaunch; confirm local-history behavior matches the UI and privacy policy.
- [ ] Diagnostics, notifications, issue text, exports, and logs reviewed for credentials, usernames in paths, and unnecessary listening metadata.
- [ ] Oldest and newest supported macOS versions on Apple silicon and Intel where supported.
- [ ] Launch-at-login registration/removal, notification denial/recovery, and uninstall-data guidance.
- [ ] Four-hour mixed-playback soak test stays within `Documentation/PERFORMANCE.md` budgets with no stale presence, duplicate scrobbles, or unbounded growth.

## Release procedure

1. Complete or explicitly accept every unchecked item above.
2. Run `swift test`, `./scripts/verify-website.sh`, `./scripts/package-app.sh`, and `./scripts/verify-package.sh` from a clean checkout.
3. Create and verify the 1.0.0 DMG and checksum.
4. Change website release-candidate language to released language and add the release date.
5. Tag `v1.0.0`; inspect the draft release artifacts before publishing.
