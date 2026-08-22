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

CloudKit coordination is optional and is not enabled in the default personal-team build. A free Apple ID can install and use the local queue and Last.fm submission path without it.

The app creates a `PresenceFM` custom zone in the configured private database. During development, run both apps once to create `PresenceAccount`, `Listen`, `Evidence`, `Device`, `SyncCursor`, and `SubmissionGate` record types. Inspect them in CloudKit Console before physical two-device testing. The database contains evidence and coordination state, never Last.fm keys or session tokens.

## Physical-device checklist

Record observed, reconciled, uncertain, missed, and duplicate counts for foreground, locked, force-quit, offline, repeat, seek, local-file, and simultaneous Mac/iPhone sessions. A public reliability claim must not be added until the matrix contains measured results.

The iPhone home screen now reports detecting, progressing, queued, submitted,
excluded, private, and needs-attention states through the same presentation
contract used by the Mac app. Validate that every blocking state offers one
working recovery action and that locked, suspended, and force-quit scenarios are
described as iOS runtime limitations rather than continuous background capture.

Historical reconciliation is user-confirmed. PresenceFM follows every page
available from MusicKit's recently-played songs response and places new
candidates in **Choose Past Plays**. Nothing in that inbox is submitted until
the user selects individual songs or uses **Select All** and taps the scrobble
button. MusicKit does not expose a complete event log: its list can omit older
history and can collapse repeated plays of the same song into one last-played
entry, so the UI must not describe this import as complete Apple Music history.

| Scenario | Observed | Reconciled | Uncertain | Submitted | Missed | Duplicate | Evidence / notes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Foreground playback | — | — | — | — | — | — | Physical device required |
| Locked / suspended | — | — | — | — | — | — | Physical device required |
| Force-quit then relaunch | — | — | — | — | — | — | Physical device required |
| Offline then reconnect | — | — | — | — | — | — | Physical device required |
| Repeat and seek | — | — | — | — | — | — | Physical device required |
| Local Music file | — | — | — | — | — | — | Physical device required |
| Simultaneous Mac / iPhone | — | — | — | — | — | — | Cloud-enabled build required |
