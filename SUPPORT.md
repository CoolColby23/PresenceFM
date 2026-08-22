# Support

Search existing GitHub issues before opening a new one. Include the PresenceFM version, macOS version, affected integration, reproduction steps, and the redacted Diagnostics view. Never include Last.fm tokens, API secrets, or unredacted home-directory paths.

Unsigned builds may require approval in **System Settings → Privacy & Security**. Apple Music access is managed under **Privacy & Security → Automation**.

Apple Music and Spotify are detected automatically. YouTube Music requires YTMDesktop 2 with its local Companion Server and companion authorization enabled. TIDAL is detected through macOS Now Playing metadata and is best effort because TIDAL does not expose a public macOS playback API. Include the affected player and its version in provider reports.

For iPhone companion reports, include the iOS version, whether Music access is granted, the history-import filter used, and the status shown for the affected song. Do not attach screenshots containing Last.fm credentials. Because iOS can suspend apps in the background, distinguish a historical import result from a continuously observed play when describing the issue.

## Uninstall and local data

Before removing PresenceFM, turn off **Launch PresenceFM at login** in Settings.
Quit the app, then move PresenceFM from Applications to the Trash.

Removing the app intentionally leaves local history, queued scrobbles, settings,
credentials, and recovery backups in place for a later reinstall. To remove that
data too, delete `~/Library/Application Support/PresenceFM` and run
`defaults delete fm.presence.PresenceFM` in Terminal. This is permanent; export
a PresenceFM backup first if the history or queue should be preserved.

Automation and notification permissions are managed by macOS and can be removed
separately under **System Settings → Privacy & Security** and **Notifications**.
