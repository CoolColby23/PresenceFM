# PresenceFM

PresenceFM is a native macOS menu-bar app that reads current playback from Apple Music, Spotify, YouTube Music through YTMDesktop, or TIDAL, publishes optional Discord Rich Presence, and scrobbles qualified listens to Last.fm. It runs locally, starts private, and requires no PresenceFM account or backend.

## OpenAI Build Week judge quickstart

PresenceFM is entered in **Apps for Your Life**. Judges can exercise the real
now-playing, scrobble-eligibility, and listening-history pipeline without music
accounts or credentials:

```sh
swift test
swift run PresenceFM --demo
```

The `--demo` launch skips onboarding for that run and immediately rotates short
sample tracks through the production playback pipeline. It does not change the
saved onboarding preference. Demo data is never published to Discord or Last.fm;
completed demo listens remain local so the history and insights screens become
testable after about a minute. Demo playback can also be started from the empty
Now Playing dashboard or **Settings → Demo Mode**.

See [Documentation/OPENAI-BUILD-WEEK.md](Documentation/OPENAI-BUILD-WEEK.md)
for the problem statement, architecture, Codex/GPT-5.6 build notes, and judging
path. The concise recording plan is in
[Documentation/BUILD-WEEK-DEMO-SCRIPT.md](Documentation/BUILD-WEEK-DEMO-SCRIPT.md).
Entrant-only video, identity, `/feedback`, and final-submit steps are in
[Documentation/BUILD-WEEK-FINAL-SUBMISSION.md](Documentation/BUILD-WEEK-FINAL-SUBMISSION.md).

## Version 1.0 release candidate

The repository now builds as `1.0.0`, but the public 1.0 release remains gated
on the account-, hardware-, and OS-dependent checks in
[Documentation/QA-1.0.0-RC.md](Documentation/QA-1.0.0-RC.md). Until those are
recorded, GitHub's latest published release remains the stable download.

### Highlights

- Apple Music, Spotify, YouTube Music through YTMDesktop, and best-effort TIDAL playback detection.
- Platform-aware Discord presentation with configurable lines, artwork, progress, badges, buttons, and links.
- Stricter Last.fm response validation, reliable retry behavior, privacy-redacted support reports, and a branded DMG.
- Versioned persistence migration, rollback backups, transactional backup/restore, and bounded local diagnostics.
- Expanded local insights with period comparisons, top tracks and albums, hourly listening, platform summaries, and a stable CSV v1 export.
- Keyboard shortcuts for every dashboard destination, clearer VoiceOver onboarding progress, and confirmations for destructive queue and account actions.

Listening insights are calculated entirely on this Mac from PresenceFM's local activity records. They are never uploaded by PresenceFM.

## Rich Now Playing

- Rich Now Playing in both the dashboard and menu bar, with album artwork, playback time, and platform-aware listening links.
- Live scrobble eligibility progress plus clearer queued, submitted, and ineligible states.
- Searchable local listening activity and direct recovery actions when a service needs attention.
- Timed Private Mode that automatically resumes integrations when the selected period ends.
- Actionable, deduplicated notifications for permission loss, expired Last.fm authorization, and persistently stuck scrobbles.

Artwork is read from Apple Music and stored only in a bounded temporary cache. Missing or unsupported artwork falls back to the PresenceFM mark.

## Requirements

- macOS 15 or later
- Xcode 26 or later for source builds
- Apple Music or Spotify for automatic live playback detection; Demo Mode requires neither
- YTMDesktop 2 with its local Companion Server for YouTube Music
- TIDAL through macOS Now Playing metadata (best effort because TIDAL has no public macOS playback API)
- Discord Desktop and/or a Last.fm account for optional integrations

## Install

1. Download the `.dmg` and `.sha256` files from GitHub Releases.
2. Verify with `shasum -a 256 -c PresenceFM-*.sha256`.
3. Open the disk image and drag PresenceFM to Applications.
4. Open PresenceFM. For an older unsigned release, Control-click PresenceFM and choose **Open**; if macOS still blocks it, approve it under **System Settings → Privacy & Security**.
5. Approve Apple Music Automation access when prompted.

PresenceFM releases are ad-hoc signed because the project does not use a paid Apple Developer account. macOS cannot notarize these builds, so the first launch requires the Control-click **Open** flow described above.

## Build from source

```sh
swift build
swift test
./scripts/package-app.sh
./scripts/verify-package.sh
open PresenceFM.app
```

PresenceFM includes Discord application ID `1525555974390153346`. Development builds can still override it under **Settings → Advanced** or with `PRESENCEFM_DISCORD_APPLICATION_ID` while packaging.

Each user supplies their own Last.fm API key and shared secret during onboarding. To avoid repeated macOS Keychain prompts in ad-hoc signed releases, PresenceFM stores those credentials and the resulting session token in `~/Library/Application Support/PresenceFM/credentials.json`, readable only by the current macOS user. They are never bundled into releases.

## Scrobbling behavior

A track becomes eligible after listening to 50% of its duration or four minutes, whichever comes first. Tracks of 30 seconds or less, radio streams, and tracks with incomplete metadata are not scrobbled. Eligible submissions are deduplicated and retained locally for retry when Last.fm is unavailable.

See [PLAN.md](PLAN.md) for planned work, plus [PRIVACY.md](PRIVACY.md),
[SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md), and
[CONTRIBUTING.md](CONTRIBUTING.md). Release history is maintained in
[CHANGELOG.md](CHANGELOG.md).
