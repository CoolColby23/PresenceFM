# Performance and Soak-Test Procedure

Use a supported Apple-silicon Mac with a release build and Activity Monitor sampling over at least five minutes per state.

Targets are under 1% average CPU while idle, under 3% while playing, under 150 MB steady-state memory, and under two seconds from launch to a usable dashboard. Verify artwork remains within 12 memory and 40 disk entries, diagnostics within 1,000 entries, and health history within 200 entries.

For the four-hour soak test, alternate play, pause, seek, skip, provider switching, network loss/recovery, Discord restart, and Private Mode. Record app/macOS/player versions, average and peak CPU/memory, queue counts, cache counts, and any stale presence or duplicate scrobble. This procedure requires manual release QA and cannot be replaced by a unit test.
