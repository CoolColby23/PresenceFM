# Performance and Soak-Test Procedure

Use a supported Apple-silicon Mac with a release build and Activity Monitor sampling over at least five minutes per state.

Targets are under 1% average CPU while idle, under 3% while playing, under 150 MB steady-state memory, and under two seconds from launch to a usable dashboard. Verify artwork remains within 12 memory and 40 disk entries, diagnostics within 1,000 entries, and health history within 200 entries.

The Diagnostics screen reports the latest total poll latency and the latency of each provider that participated. For sustained evidence, record the `PlaybackPolling` signposts with Instruments in an optimized build; the `Playback poll` interval covers provider reads and source selection. Compare the same idle and playing scenario before and after polling changes.

| State | Average CPU | Peak CPU | Memory | Average poll | Peak poll |
| --- | ---: | ---: | ---: | ---: | ---: |
| Idle | Not recorded | Not recorded | Not recorded | Not recorded | Not recorded |
| Playing | Not recorded | Not recorded | Not recorded | Not recorded | Not recorded |

## 1.0 release-candidate spot check

On July 21, 2026, the signed 1.0.0 (1000) release build was sampled every two seconds for 24 seconds on Apple silicon after the dashboard reached a settled, idle state. CPU settled at 0.0% and memory settled between 130.2 and 130.4 MB (about 127.3 MiB). The highest startup-settling sample was 1.1% CPU and 224.6 MB. This is a diagnostic spot check only; it does not replace the five-minute state measurements or four-hour mixed-playback soak test required above.

For the four-hour soak test, alternate play, pause, seek, skip, provider switching, network loss/recovery, Discord restart, and Private Mode. Record app/macOS/player versions, average and peak CPU/memory, queue counts, cache counts, and any stale presence or duplicate scrobble. This procedure requires manual release QA and cannot be replaced by a unit test.
