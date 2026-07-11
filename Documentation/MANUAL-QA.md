# Public v0.1 Manual QA

Record the app version, macOS version, and pass/fail evidence for every item. Do not attach secrets or unredacted personal paths.

## Clean installation and Apple Music

- Verify the release archive checksum, move the unsigned app to Applications, and complete the documented Gatekeeper flow.
- Deny Apple Music Automation once; confirm the app shows permission required, publishes nothing, and explains recovery.
- Grant Automation access and confirm playing, paused, stopped, local-file, and unsupported radio states.
- Seek forward and backward, pause for several minutes, change tracks, quit Music, and relaunch PresenceFM. Confirm listening time and recent activity remain credible.

## Discord

- Start with Discord closed and confirm an offline state without repeated prompts or crashes.
- Launch Discord, play a track, and confirm title, artist/album, and timer settings.
- Pause playback, enable Private Mode, quit Music, and quit PresenceFM; confirm presence clears in each case.
- Relaunch Discord and PresenceFM and confirm presence recovers without rerunning onboarding.

## Last.fm and queue

- Authorize a test account and verify the connected username.
- Confirm now-playing appears promptly and a qualified listen scrobbles exactly once.
- Confirm short tracks, streams, skipped tracks, and Private Mode do not scrobble.
- Disconnect networking through the eligibility point, relaunch PresenceFM, reconnect, and confirm the queued scrobble submits once.
- Revoke the Last.fm session and confirm authorization-expired state plus a usable reauthorization path.
- Disconnect Last.fm in Settings and confirm scrobbling is disabled while the API key and shared secret remain available for reauthorization.
- Exercise retry and remove actions on failed queue records.

## Lifecycle and compatibility

- Close the dashboard while leaving the menu-bar item active; confirm monitoring continues.
- Verify launch at login registration and removal.
- Run on macOS 15–25 and confirm standard materials/buttons render correctly.
- Run on macOS 26 and confirm Liquid Glass styling renders correctly.
- Review Diagnostics and GitHub issue text for tokens, application secrets, usernames in paths, or other sensitive data.
