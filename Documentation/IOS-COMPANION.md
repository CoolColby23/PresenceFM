# iOS companion architecture and validation

The source-built iOS 18 app watches the public Music system player while iOS grants runtime. It records strong evidence only when playback position advances naturally. MusicKit reconciliation can identify later candidates, but missing timestamps or duration are sent to Review and never silently reconstructed.

## Capability matrix

These rows are deliberately marked **device validation required** until exercised with the capture diagnostics harness.

| Scenario | Expected public surface | Automatic action |
| --- | --- | --- |
| Foreground Music playback | System player item, state, position | Track and scrobble at threshold |
| Brief background transition | Last foreground evidence plus opportunistic runtime | Persist and reconcile |
| Long background/locked | System-scheduled refresh only | Reconcile; uncertain items go to Review |
| Force-quit | No execution | Reconcile on next launch |
| Non-library Apple Music | MusicKit metadata varies | Submit only with timestamp and eligibility evidence |
| Local Music file | MediaPlayer metadata where exposed | Track when title, artist, duration, and position exist |
| Offline | Local durable queue | Submit after connectivity and lease recovery |

Never use silent audio, location, or unrelated background modes to prolong execution.

## CloudKit development schema

The app creates a `PresenceFM` custom zone in the configured private database. During development, run both apps once to create `PresenceAccount`, `Listen`, `Evidence`, `Device`, `SyncCursor`, and `SubmissionGate` record types. Inspect them in CloudKit Console before physical two-device testing. The database contains evidence and coordination state, never Last.fm keys or session tokens.

## Physical-device checklist

Record observed, reconciled, uncertain, missed, and duplicate counts for foreground, locked, force-quit, offline, repeat, seek, local-file, and simultaneous Mac/iPhone sessions. A public reliability claim must not be added until the matrix contains measured results.
