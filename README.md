# PresenceFM

PresenceFM is a native macOS menu-bar app that reads the current Apple Music track, publishes optional Discord Rich Presence, and scrobbles qualified listens to Last.fm. It runs locally, starts private, and requires no PresenceFM account or backend.

## Highlights in 0.3.0

- Private Listening History with search, filters, total listening time, top artists, and a seven-day activity chart.
- CSV export plus configurable local retention and clear-history controls.
- Rich Now Playing in both the dashboard and menu bar, with locally sourced album artwork, playback time, and Apple Music links.

Listening insights are calculated entirely on this Mac from PresenceFM's local activity records. They are never uploaded by PresenceFM.

## Rich Now Playing

- Rich Now Playing in both the dashboard and menu bar, with locally sourced album artwork, playback time, and Apple Music links.
- Live scrobble eligibility progress plus clearer queued, submitted, and ineligible states.
- Searchable local listening activity and direct recovery actions when a service needs attention.
- Timed Private Mode that automatically resumes integrations when the selected period ends.
- Actionable, deduplicated notifications for permission loss, expired Last.fm authorization, and persistently stuck scrobbles.

Artwork is read from Apple Music and stored only in a bounded temporary cache. Missing or unsupported artwork falls back to the PresenceFM mark.

## Requirements

- macOS 15 or later
- Xcode 26 or later for source builds
- Apple Music for playback detection
- Discord Desktop and/or a Last.fm account for optional integrations

## Install

1. Download the `.zip` and `.sha256` files from GitHub Releases.
2. Verify with `shasum -a 256 -c PresenceFM-*.sha256`.
3. Unzip the app and move it to `/Applications`.
4. Open PresenceFM. For an older unsigned release, Control-click PresenceFM and choose **Open**; if macOS still blocks it, approve it under **System Settings → Privacy & Security**.
5. Approve Apple Music Automation access when prompted.

The release workflow signs and notarizes builds when the repository's Apple Developer credentials are configured. Otherwise it produces an unsigned draft release for testing; replacing an unsigned build may cause macOS to request Automation access again.

## Build from source

```sh
swift build
swift test
./scripts/package-app.sh
open PresenceFM.app
```

PresenceFM includes Discord application ID `1525555974390153346`. Development builds can still override it under **Settings → Advanced** or with `PRESENCEFM_DISCORD_APPLICATION_ID` while packaging.

Each user supplies their own Last.fm API key and shared secret during onboarding. PresenceFM stores those credentials and the resulting session token in macOS Keychain; they are never bundled into releases.

## Scrobbling behavior

A track becomes eligible after listening to 50% of its duration or four minutes, whichever comes first. Tracks of 30 seconds or less, radio streams, and tracks with incomplete metadata are not scrobbled. Eligible submissions are deduplicated and retained locally for retry when Last.fm is unavailable.

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md), and [CONTRIBUTING.md](CONTRIBUTING.md).
