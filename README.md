# PresenceFM

PresenceFM is a native macOS menu-bar app that reads the current Apple Music track, publishes optional Discord Rich Presence, and scrobbles qualified listens to Last.fm. It runs locally, starts private, and requires no PresenceFM account or backend.

## Requirements

- macOS 15 or later
- Xcode 26 or later for source builds
- Apple Music for playback detection
- Discord Desktop and/or a Last.fm account for optional integrations

## Install an unsigned release

1. Download the `.zip` and `.sha256` files from GitHub Releases.
2. Verify with `shasum -a 256 -c PresenceFM-*.sha256`.
3. Unzip the app and move it to `/Applications`.
4. Control-click PresenceFM and choose **Open**. If macOS still blocks it, approve it under **System Settings → Privacy & Security**.
5. Approve Apple Music Automation access when prompted.

PresenceFM releases are currently unsigned and unnotarized. Replacing an unsigned build may cause macOS to request Automation access again.

## Build from source

```sh
swift build
swift test
./scripts/package-app.sh
open PresenceFM.app
```

Local builds work without bundled Discord configuration by using a custom Discord Application ID under **Settings → Advanced**. Official releases inject PresenceFM's Discord Application ID from a GitHub Actions secret.

Each user supplies their own Last.fm API key and shared secret during onboarding. PresenceFM stores those credentials and the resulting session token in macOS Keychain; they are never bundled into releases.

## Scrobbling behavior

A track becomes eligible after listening to 50% of its duration or four minutes, whichever comes first. Tracks of 30 seconds or less, radio streams, and tracks with incomplete metadata are not scrobbled. Eligible submissions are deduplicated and retained locally for retry when Last.fm is unavailable.

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md), and [CONTRIBUTING.md](CONTRIBUTING.md).
