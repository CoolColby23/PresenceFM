# Privacy

PresenceFM runs locally and has no PresenceFM account or backend. It reads current playback metadata from enabled local providers, sends enabled presence data directly to Discord Desktop, and sends enabled scrobbles directly to Last.fm. Apple Music and Spotify use AppleScript, YouTube Music uses the local YTMDesktop Companion Server, and TIDAL uses the macOS Now Playing metadata surface.

User-provided Last.fm API credentials and session tokens are stored in an owner-only file under `~/Library/Application Support/PresenceFM`. Any custom Discord Application ID override and other preferences are stored in `UserDefaults`. Recent activity, queued scrobbles, and redacted diagnostics are stored locally with SwiftData. PresenceFM does not intentionally collect telemetry or analytics.

Listening totals, charts, top artists, searches, and exports are calculated locally from those activity records. Users can choose a retention period, clear history at any time, and explicitly select a destination when exporting CSV data.

User-initiated PresenceFM backups contain listening history, non-submitted queue records, and non-secret preferences. They exclude credentials, authorization tokens, artwork, diagnostics, health history, and machine-specific paths. Before restore, PresenceFM keeps up to two automatic local rollback backups under Application Support. PresenceFM never uploads backup files.

Album artwork is read locally from the currently playing Apple Music track and kept in a bounded temporary cache for display. To show cover art on Discord, PresenceFM sends the current track title, artist, and album to Apple's public catalog search and gives Discord the matched Apple-hosted artwork URL. PresenceFM never uploads local artwork bytes or sends them to its own service. Notification content contains only recovery guidance and, for a stuck scrobble, the affected track title.

Private Mode clears Discord presence and suppresses Last.fm updates. Removing the app does not automatically remove its local application data.
