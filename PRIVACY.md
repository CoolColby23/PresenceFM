# Privacy

PresenceFM runs locally and has no PresenceFM account or backend. It reads current playback metadata from Apple Music through macOS Automation, sends enabled presence data directly to Discord Desktop, and sends enabled scrobbles directly to Last.fm.

User-provided Last.fm API credentials, Last.fm session tokens, and any custom Discord Application ID override are stored in macOS Keychain. Preferences are stored in `UserDefaults`. Recent activity, queued scrobbles, and redacted diagnostics are stored locally with SwiftData. PresenceFM does not intentionally collect telemetry or analytics.

Private Mode clears Discord presence and suppresses Last.fm updates. Removing the app does not automatically remove its Keychain items or local application data.
