# PresenceFM 1.0.0 Release-Candidate QA

Updated: 2026-08-01

This is the release decision record for 1.0.0. A checked item has reproducible
evidence; an unchecked item is a release blocker unless the maintainer records
an explicit, user-visible accepted risk before publication.

## Automated and package gates

- [x] At implementation commit `44de90b`, debug `swift test` passes on arm64 macOS 27.0 (26A5388g): 88 tests across 17 suites, including Discord customization, per-provider monitor reporting, Apple Music Radio eligibility/queue transport, demo playback, backup/extended-insight behavior, empty-period comparison behavior, duplicate observable-status suppression, and bounded oldest-first health-history retention. The earlier optimized Private Mode expiration check also passed 10 repeated runs.
- [x] Address Sanitizer and Thread Sanitizer test runs pass with no reported memory or data-race issue.
- [x] At implementation commit `44de90b`, the release app builds, receives an Apple Development signature, and passes strict bundle verification as 1.0.0 build 1. The 4,595,639-byte DMG passes `hdiutil verify` with SHA-256 `f943d5d23b28c0e167c3300265a259b52e2a71adf2c5e68db9968b50d60f597e`.
- [x] Pull-request CI uses pinned Xcode 26.0, tests Swift code with a coverage report, checks patch hygiene, verifies the website, packages the app, and verifies the DMG.
- [x] Tagged releases reject a tag that disagrees with `VERSION`, verify the website and DMG/checksum, then create a draft release with DMG and checksum artifacts.
- [x] Website metadata, fragments, local assets, sitemap, and robots file pass the dependency-free integrity check.
- [x] The verified 1.0.0 build 1 bundle from implementation commit `44de90b` was installed in `/Applications` on the arm64 macOS 27.0 test machine; its executable SHA-256 matches the packaged source bundle and the app remained running in Demo Mode after launch.
- [x] GitHub Pages deployment is defined for website changes on `main`.

## App interaction evidence

- [x] Dashboard sections render with live playback and integration status.
- [x] Command-1 through Command-5 navigate to the five dashboard destinations without opening duplicate windows.
- [x] Shift-Command-P enters Private Mode, updates the controls, and exits again without opening another window.
- [x] The packaged 1.0.0 app launches in Demo Mode on macOS 27.0 (26A5388g); Now Playing, playback/scrobble progress, service state, Listening History cards, empty Queue, Diagnostics, and all five Settings categories render without visible clipping at the supported window size.
- [x] Last.fm disconnection presents consequences and can be canceled without changing the account.
- [x] Onboarding exposes its current step to accessibility and supports Return navigation. A returning user can close the tour with its labeled Close button or Escape, and rerunning it preloads the current player, integration, and launch-at-login preferences.
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

## Current go/no-go decision

**NO-GO as of August 1, 2026.** Automated tests, new-file formatting, patch
hygiene, website verification, release packaging, bundle verification, DMG
verification, and the five-minute idle resource budget pass on the arm64 macOS
27.0 machine. The packaged process also launches with `--demo`.

The following evidence is still required and is not represented as a pass:

- The local macOS accessibility bridge did not return the packaged app's window
  tree, so the current package does not have a newly recorded keyboard,
  VoiceOver, increased-contrast, reduced-motion, or narrow-window traversal.
- The clean five-minute accelerated Demo Mode sample at `44de90b` passes the
  playing CPU and memory budgets at 2.252% average CPU and 119.0 MiB average
  resident memory. It does not substitute for normal account-backed playback;
  poll latency, launch timing, and the four-hour soak remain unverified.
- Live Apple Music, Spotify, YTMDesktop, TIDAL, Discord, and Last.fm account
  matrices were not exercised during this verification run.
- macOS 15 through 26 and Intel coverage are unavailable. These are unaccepted
  risks, not passes; publishing requires either compatible test evidence or an
  explicit maintainer acceptance recorded in this file and the public release
  notes with the likely user impact.
- The production GitHub Pages URL still requires confirmation after the Pages
  workflow runs on `main`.

## Release procedure

1. Complete or explicitly accept every unchecked item above.
2. Run `swift test`, `./scripts/verify-website.sh`, `./scripts/package-app.sh`, and `./scripts/verify-package.sh` from a clean checkout.
3. Create and verify the 1.0.0 DMG and checksum.
4. Change website release-candidate language to released language and add the release date.
5. Tag `v1.0.0`; inspect the draft release artifacts before publishing.
