# PresenceFM 0.4.0 QA Record

Date: 2026-07-12

Environment: Apple silicon Mac, macOS 26 development environment, Swift 6.2 / Xcode 26+

## Automated verification

- `swift test`: pass, 65 tests across 13 suites.
- `swift build -c release`: pass.
- Packaged application signing and strict signature verification: pass.
- Issue-template and workflow YAML parsing: pass.
- `git diff --check`: pass.
- DMG creation and `hdiutil verify`: pass.
- Packaged metadata: PresenceFM 0.4.0 (build 1), minimum macOS 15.
- Packaged SwiftPM resources, app icon, Apple Events usage text and entitlement,
  Discord application ID, and runtime-reported 0.4.0 version: pass.
- Pull-request CI mirrors tests, patch hygiene, release packaging, app-bundle
  verification, DMG creation, and DMG verification.

## Computer Use verification

- Dashboard launches and reports live Apple Music metadata, playback progress,
  Discord connectivity, Last.fm recovery state, and Private Mode controls.
- Settings render the Discord display controls and all four music-platform paths.
- Diagnostics reports runtime version 0.4.0 and the redacted support-report copy
  action confirms completion without exposing credentials or listening metadata.
- DMG mounts with PresenceFM and Applications arranged in a branded Finder window.
- Installer background was iterated after visual inspection to provide contrast
  behind Finder's fixed black icon labels.
- Final DMG inspection confirms a visible white right-pointing drag arrow between
  PresenceFM and Applications without obscuring either icon or label.

## Deterministic integration coverage

- Discord external artwork, neutral artwork tooltip, fallback asset, PresenceFM
  small logo, and Spotify platform-logo payloads.
- YTMDesktop Companion Server state parsing, progress, metadata, link generation,
  and live-stream scrobble exclusion.
- Spotify playing, paused, stopped, and malformed-state parsing; source priority,
  provider loss/recovery, and Apple Music permission failure with Spotify active.
- Discord hidden small-image/timer/link combinations, automatic platform button
  labels, and album-line fallbacks.
- Discord start/end track progress, artwork hover context, platform badge, blank
  fallback, and 128-character field bounding.
- Last.fm temporary authorization token isolation, signed form fields, accepted
  scrobble validation, ignored-scrobble rejection, retries, permanent failures,
  and overlapping queue-drain deduplication.

## Account-dependent follow-up

Live YTMDesktop, Spotify, TIDAL, and Last.fm account checks require those desktop
apps/accounts to be present. They were unavailable in this environment. Discord
and Apple Music were available for packaged-app inspection. Complete the remaining
account rows in `Documentation/MANUAL-QA.md` before publishing the release.

These checks remain open release gates, not implied passes. Publishing without them requires an explicit accepted-risk note naming each untested provider, account flow, macOS range, and hardware architecture.
