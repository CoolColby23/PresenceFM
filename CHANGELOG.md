# Changelog

## 0.3.0 - Unreleased

- Added a private Listening History dashboard with search, period and outcome filters.
- Added local listening totals, listening time, top artists, and a seven-day activity chart.
- Added CSV export, clear-history controls, and configurable 30-day, 90-day, one-year, or unlimited retention.
- Increased the bounded local activity history from 200 to 5,000 records.
- Bundled Discord application ID `1525555974390153346` for development and packaged builds.
- Added locally cached Apple Music artwork and richer now-playing layouts in the dashboard and menu bar.
- Added playback timing, scrobble eligibility progress, clearer queue states, and searchable recent activity.
- Made integration preferences update Discord and Last.fm immediately.
- Added scheduled Private Mode expiration with automatic Discord presence recovery.
- Added deduplicated recovery notifications for Music permission, Last.fm authorization, and stuck scrobbles.
- Added direct recovery actions for Automation permission, Discord reconnection, Last.fm reauthorization, and queue retries.
- Added a responsive, dependency-free project website and canonical brand asset set.
- Added conditional Developer ID signing and Apple notarization to tagged release builds.
- Reduced song-change latency for the dashboard, Discord presence, and Last.fm now-playing updates.
- Made artwork transitions clear stale covers immediately, retry Apple Music artwork, and fall back to Apple-hosted catalog artwork.
- Added dynamic album artwork to Discord Rich Presence with the PresenceFM mark as an immediate fallback.
- Removed Keychain access entirely to eliminate password prompts in unsigned and ad-hoc signed builds; Last.fm credentials now live in an owner-only local file.
- Made packaging fall back to ad-hoc signing when no Apple signing identity is available, so releases do not require a paid developer account.

## 0.1.0

- Apple Music playback monitoring on macOS 15 and later.
- Discord Rich Presence and Last.fm now-playing/scrobbling.
- Private mode, persistent offline queue, diagnostics, onboarding, and unsigned release packaging.
