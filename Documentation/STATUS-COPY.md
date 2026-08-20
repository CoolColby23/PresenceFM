# Integration Status and Recovery Language

PresenceFM uses one status vocabulary everywhere: menu bar, dashboard, settings,
notifications, diagnostics, and exported support text. `ServiceStatus` is the
source of truth for labels; recovery button titles come from `IntegrationID`.

## Canonical status names

| Status | Presentation label | Meaning |
| --- | --- | --- |
| `disabled` | Disabled | Integration is turned off by the user. |
| `inactive` | Not active | Enabled, but not currently participating. |
| `awaitingPermission` | Permission required | macOS Automation or equivalent access is missing. |
| `connecting` | Connecting | Startup or reconnect in progress. |
| `connected` | Connected | Healthy and ready to publish or monitor. |
| `offline` | Offline | Remote app or network path is unavailable. |
| `authorizationExpired` | Authorization expired | Saved credentials or session were rejected. |
| `failed` | Needs attention | Actionable failure; detail text carries the cause. |

Failed states always show **Needs attention** as the short label. The detailed
message (for example “Permission denied”) appears only as secondary copy so the
same failure is not renamed across surfaces.

## Recovery actions

| Integration | Recovery title | Destination |
| --- | --- | --- |
| Apple Music | Open Settings | System Settings / Automation recovery path |
| Discord | Reconnect | Discord connection controls |
| Last.fm | Reconnect | Last.fm authorization controls |
| YouTube Music | Reconnect | YTMDesktop companion authorization |
| Spotify | — | No dedicated button; status explains the player state |
| TIDAL | — | No dedicated button; best-effort Now Playing surface |

Notifications and diagnostics must reuse these names rather than inventing
synonyms such as “Disconnected”, “Error”, or “Auth failed”.

## Demo Mode

While Demo Mode is active, Discord and Last.fm may show **Paused for demo** as a
temporary override. That override is presentation-only and does not change the
underlying integration configuration.
