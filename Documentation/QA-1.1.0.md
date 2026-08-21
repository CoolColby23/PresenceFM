# PresenceFM 1.1.0 Release QA

Updated: 2026-08-20

This is the living release record for PresenceFM 1.1.0. Automated evidence is
recorded separately from checks that require a human, real service accounts,
specific hardware, or Apple distribution credentials. An unchecked manual gate
must not be represented as passed.

## Automated and repository gates

- [x] Swift tests, formatting, website integrity, release packaging, bundle
  verification, DMG verification, and checksum generation pass for
  `v1.1.0-beta.2` in GitHub Actions run 32433126707.
- [x] The public production website resolves at
  `https://presence-fm.vercel.app/`, advertises beta 2, has no missing images,
  and has no horizontal overflow at 1440×900 or 390×844.
- [x] Repository secret scanning and push protection are enabled, with no
  secret-scanning alerts at this audit.
- [x] GitHub Actions are SHA-pinned and `main` requires the test, package, and
  preview checks.
- [x] A dedicated Sparkle EdDSA private key is stored as the encrypted
  `SPARKLE_PRIVATE_KEY` GitHub Actions secret. The matching public key is
  embedded by `scripts/package-app.sh`.

## Accessibility audit

- [x] The installed app accessibility tree exposes labeled dashboard
  navigation, privacy controls, playback controls and progress, history view
  modes and filters, queue state, diagnostics, settings search/categories, and
  onboarding controls.
- [x] Onboarding announces its step and supports Return to continue and Escape
  to close. Dashboard destinations and Private Mode have documented keyboard
  shortcuts.
- [x] Destructive queue/account actions require confirmation and icon-only
  provider-reorder controls have concrete accessibility labels.
- [x] Playback progress uses a spoken value bounded to 15-second changes.
- [x] Animated branding and now-playing track transitions respect Reduce
  Motion. Theme foreground/background pairs are regression-tested at WCAG AA
  4.5:1 contrast.
- [x] Native SwiftUI controls and scalable system text are used instead of
  fixed bitmap text, preserving macOS display-size behavior.

No release-blocking accessibility defect was found in the code and local AX
tree audit. A human VoiceOver listening pass and alternate macOS display-setting
pass remain recommended compatibility coverage, not evidence supplied by
automation.

## Distribution decision

PresenceFM is intentionally distributed with an ad-hoc signature until a
Developer ID Application certificate and Apple notarization credentials are
available. The Gatekeeper first-launch flow is documented in the README and
release notes. This is an explicitly accepted distribution limitation; it must
not be described as notarized.

Sparkle update signing is configured. A production `v1.1.0` tag must still be
tested as a draft before publication so its generated appcast and signature can
be verified against an older build.

## Manual account and hardware gates

Use `Documentation/MANUAL-QA.md` to record the remaining live Apple Music,
Spotify, YTMDesktop, TIDAL, Discord, Last.fm, sleep/wake, upgrade, and four-hour
soak evidence. These checks require the relevant accounts, applications,
permissions, elapsed time, or additional hardware and cannot be truthfully
completed by repository automation.
