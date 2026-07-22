# PresenceFM Release Manual QA

Record the app version, macOS version, and pass/fail evidence for every item. Do not attach secrets or unredacted personal paths.

## Clean installation and Apple Music

- Verify the release archive checksum, move the app to Applications, and confirm its signature/notarization. For an unsigned test build, complete the documented Gatekeeper flow.
- Deny Apple Music Automation once; confirm the app shows permission required, publishes nothing, and explains recovery.
- Grant Automation access and confirm playing, paused, stopped, local-file, and Apple Music radio states.
- Seek forward and backward, pause for several minutes, change tracks, quit Music, and relaunch PresenceFM. Confirm listening time and recent activity remain credible.
- Confirm album artwork appears without delaying metadata updates, changes with the track, and falls back to the PresenceFM mark when unavailable.
- Confirm elapsed/remaining playback time and scrobble eligibility progress remain correct while playing, paused, and seeking.

## Spotify, YouTube Music, and TIDAL

- With Apple Music stopped, verify Spotify play, pause, seek, skip, app quit, and relaunch behavior, including platform-aware links and Discord branding.
- Enable YTMDesktop 2's Companion Server and authorization, connect from PresenceFM, and verify play, pause, seek, skip, token rejection, disconnect, and reconnect behavior.
- Verify YouTube Music live streams are visible but never scrobbled.
- Verify TIDAL playback through macOS Now Playing for play, pause, seek, skip, app quit, sleep/wake, and relaunch. Record the macOS and TIDAL versions because this provider uses a best-effort system metadata surface.
- Play from two providers simultaneously and verify PresenceFM selects one deterministically, changes source without duplicate activity, and recovers when the selected provider closes.
- Confirm a permission or metadata failure in one provider does not hide valid playback from another.

## Discord

- Start with Discord closed and confirm an offline state without repeated prompts or crashes.
- Launch Discord, play a track, and confirm title, artist/album, and timer settings.
- Pause playback, enable Private Mode, quit Music, and quit PresenceFM; confirm presence clears in each case.
- Relaunch Discord and PresenceFM and confirm presence recovers without rerunning onboarding.
- Change album, timer, and link options during playback and confirm Discord presence refreshes immediately.
- Use timed Private Mode, sleep and wake the Mac across its expiration, and confirm presence resumes at the expected time.

## Last.fm and queue

- Authorize a test account and verify the connected username.
- Confirm now-playing appears promptly and a qualified listen scrobbles exactly once.
- Confirm short tracks, unsupported live streams, skipped tracks, and Private Mode do not scrobble.
- Confirm an Apple Music Radio song with title and artist metadata uses the normal threshold when duration is available, or 30 observed seconds when it is unknown; it should scrobble exactly once after its metadata changes and be marked as radio-selected without an invented duration.
- Confirm Apple Music Radio still has no finite progress/timer when duration is unavailable; a radio song that changes before eligibility remains local as Listened.
- Confirm a brief stopped/metadata gap does not create a false Skipped history row, while an actual playing-track replacement before threshold still does.
- Disconnect networking through the eligibility point, relaunch PresenceFM, reconnect, and confirm the queued scrobble submits once.
- Revoke the Last.fm session and confirm authorization-expired state plus a usable reauthorization path.
- Disconnect Last.fm in Settings and confirm scrobbling is disabled while the API key and shared secret remain available for reauthorization.
- Exercise retry and remove actions on failed queue records.
- Search recent activity by title, artist, and album; confirm empty and no-match states are distinct.

## Notifications and recovery

- Deny notifications and confirm the app continues working without repeated prompts or errors.
- Trigger lost Automation permission, expired Last.fm authorization, and three queue failures; confirm each condition produces at most one redacted notification.
- Click each notification and confirm PresenceFM opens the corresponding Diagnostics, Settings, or Queue section.
- Exercise Automation Settings, Discord reconnect, Last.fm reconnect, and queue retry actions from the app.

## Listening history

- Accumulate played and skipped tracks and confirm totals, listening minutes, artist counts, and the seven-day chart update.
- Search title, artist, and album; combine search with 7-day, 30-day, all-time, played, and skipped filters.
- Export visible history and verify CSV quoting, timestamps, filtering, and Unicode metadata in Numbers or a text editor.
- Change retention to 30 days and verify only older activity is removed. Choose Forever and verify no age-based removal occurs.
- Clear history, cancel once, then confirm deletion. Verify Last.fm history and the scrobble queue are unaffected.
- Upgrade from 0.2 data and confirm older records remain visible even when duration and listening-time details are unavailable.

## Lifecycle and compatibility

- Choose **PresenceFM → Check for Updates…** and confirm the current-version result is shown. Repeat from **Settings → Updates**.
- Toggle automatic update checks and downloads, relaunch, and confirm both preferences persist. Confirm automatic downloads are unavailable when automatic checks are disabled.
- From an older signed test build pointed at a test appcast, download and install the newer DMG in app, relaunch, and confirm the displayed version/build changed without losing local data or preferences.
- Tamper with a signed update archive and confirm PresenceFM refuses to install it.
- Close the dashboard while leaving the menu-bar item active; confirm monitoring continues.
- Verify launch at login registration and removal.
- Run on macOS 15–25 and confirm standard materials/buttons render correctly.
- Run on macOS 26 and confirm Liquid Glass styling renders correctly.
- Review Diagnostics and GitHub issue text for tokens, application secrets, usernames in paths, or other sensitive data.
