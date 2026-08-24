<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# PresenceFM

PresenceFM is a native macOS menu-bar app that reads current playback from Apple Music, Spotify, YouTube Music through YTMDesktop, or TIDAL, publishes optional Discord Rich Presence, and scrobbles qualified listens to Last.fm. It runs locally, starts private, and requires no PresenceFM account or backend.

## Download

- [Download the latest stable release](https://github.com/CoolColby23/PresenceFM/releases/latest)
- [Browse pre-releases](https://github.com/CoolColby23/PresenceFM/releases) for opt-in beta and RC builds.
- Visit [presence-fm.vercel.app](https://presence-fm.vercel.app/) for the feature overview.

Releases currently use ad-hoc signing. Follow the first-launch instructions under [Install](#install) after dragging PresenceFM to Applications.

## Demo and OpenAI Build Week quickstart

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
completed demo listens make the history and insights screens testable after about
a minute, then are removed when Demo Mode ends. Demo playback can also be started
from the empty Now Playing dashboard or **Settings → Demo Mode**.

See [Documentation/OPENAI-BUILD-WEEK.md](Documentation/OPENAI-BUILD-WEEK.md)
for the problem statement, architecture, Codex/GPT-5.6 build notes, and judging
path. The concise recording plan is in
[Documentation/BUILD-WEEK-DEMO-SCRIPT.md](Documentation/BUILD-WEEK-DEMO-SCRIPT.md).
The original submission checklist is retained in
[Documentation/BUILD-WEEK-FINAL-SUBMISSION.md](Documentation/BUILD-WEEK-FINAL-SUBMISSION.md) as project history.

## Road to version 1.2

The v1.2 work adds user-confirmed Apple Music history scrobbling on iPhone and a shared scrobble-confidence model across both apps. GitHub Releases use two channels:

- **Production** — tags like `v1.1.0` publish as Latest and update the Sparkle appcast.
- **Pre-release** — tags like `v1.1.0-beta.1` or `v1.1.0-rc.1` publish as Pre-release and never replace Latest.

The `VERSION` file is the source of truth for release builds and tags. See [CONTRIBUTING.md](CONTRIBUTING.md) for the release ladder.

### Highlights

- Apple Music, Spotify, YouTube Music through YTMDesktop, and best-effort TIDAL playback detection.
- Platform-aware Discord presentation with configurable lines, artwork, progress, badges, buttons, and links.
- Discord activity styles, elapsed or countdown timers, large/small image choices, hover text, paused-state sharing, reusable presets, and templates for track, platform, state, position, and duration.
- Stricter Last.fm response validation, reliable retry behavior, privacy-redacted support reports, and a branded DMG.
- Versioned persistence migration, rollback backups, transactional backup/restore, and bounded local diagnostics.
- Expanded local insights with period comparisons, top tracks and albums, hourly listening, platform summaries, and a stable CSV v1 export.
- Keyboard shortcuts for every dashboard destination, clearer VoiceOver onboarding progress, and confirmations for destructive queue and account actions.
- Configurable provider priority, correction-before-retry for rejected scrobbles, and metadata-free release-verification snapshots.
- Shortcuts actions for Private Mode, privacy status, and opening the dashboard.
- A menu-bar control center, reusable Discord profiles, Last.fm exclusion rules, and a shareable weekly recap.
- Authenticated encrypted iCloud backups in builds signed with the PresenceFM iCloud container entitlement.

Listening insights are calculated entirely on this Mac from PresenceFM's local activity records. They are never uploaded by PresenceFM.

The desktop WidgetKit source is ready, but widget distribution and shared live data require an Apple-signed app-group entitlement. See [Documentation/WIDGET.md](Documentation/WIDGET.md); PresenceFM does not represent that capability as shipped in ad-hoc builds.

## Rich Now Playing

- Rich Now Playing in both the dashboard and menu bar, with album artwork, playback time, and platform-aware listening links.
- Live scrobble eligibility progress plus clearer queued, submitted, and ineligible states.
- Searchable local listening activity and direct recovery actions when a service needs attention.
- Timed Private Mode that automatically resumes integrations when the selected period ends.
- Actionable, deduplicated notifications for permission loss, expired Last.fm authorization, and persistently stuck scrobbles.
- Locally advancing playback progress between provider polls, with VoiceOver announcements throttled to meaningful 15-second changes.

Provider order is configurable under **Settings → Players**. PresenceFM retains an already-playing provider to avoid false transitions; the configured order decides simultaneous starts.

The Queue screen can correct rejected title, artist, and album metadata before retrying while retaining the original listen timestamp and duplicate protection. Diagnostics can copy or save a release-verification snapshot that excludes track metadata, usernames, credentials, and paths.

PresenceFM exposes Shortcuts actions to start or end Private Mode, check privacy status, and open the dashboard.

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

After installation, PresenceFM checks the official GitHub release feed for updates. Use **PresenceFM → Check for Updates…** at any time, or manage automatic checks and downloads under **Settings → General → Updates**. Update archives are verified with PresenceFM's Sparkle EdDSA signing key before installation.

## Build from source

```sh
swift build
swift test
./scripts/package-app.sh
./scripts/verify-package.sh
open PresenceFM.app
```

### Source-built iPhone companion

The repository also contains an iOS 18 Apple Music scrobbling companion. It is not an App Store product or a distributed binary: clone the repository, use a free Apple personal team and unique bundle identifier, then enter your Last.fm application credentials during onboarding. The default build is local-only; CloudKit coordination remains an optional paid-program capability. Start with [Config/README.md](Config/README.md) and the measured-behavior checklist in [Documentation/IOS-COMPANION.md](Documentation/IOS-COMPANION.md).

Personal configuration lives in ignored `Config/Local.xcconfig`. Credentials and session tokens must never be committed.

PresenceFM includes Discord application ID `1525555974390153346`. Development builds can still override it under **Settings → Advanced** or with `PRESENCEFM_DISCORD_APPLICATION_ID` while packaging.

Each user supplies their own Last.fm API key and shared secret during onboarding. To avoid repeated macOS Keychain prompts in ad-hoc signed releases, PresenceFM stores those credentials and the resulting session token in `~/Library/Application Support/PresenceFM/credentials.json`, readable only by the current macOS user. They are never bundled into releases.

## Scrobbling behavior

A track becomes eligible after listening to 50% of its duration or four minutes, whichever comes first. Tracks of 30 seconds or less and tracks with incomplete metadata are not scrobbled. Apple Music Radio songs with usable title and artist metadata use the normal threshold when duration is available, or 30 seconds of directly observed playback when it is unknown. PresenceFM omits radio duration and marks the scrobble as radio-selected. Other unsupported live streams remain visible in Now Playing, Discord presence, and local history but are not sent to Last.fm. Eligible submissions are deduplicated and retained locally for retry when Last.fm is unavailable.

See [PLAN.md](PLAN.md) for planned work, plus [PRIVACY.md](PRIVACY.md),
[SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md), and
[CONTRIBUTING.md](CONTRIBUTING.md). Release history is maintained in
[CHANGELOG.md](CHANGELOG.md).

## Open source

PresenceFM is available under the [MIT License](LICENSE). Bug reports, focused fixes, accessibility improvements, provider reliability work, and documentation contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), and please use private vulnerability reporting for security issues.

Third-party software and service marks remain subject to their respective terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
