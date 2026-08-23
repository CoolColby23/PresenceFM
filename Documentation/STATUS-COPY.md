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

## Scrobble capture status

Integration status answers "is Last.fm reachable?". Scrobble capture status
answers "what is happening to the song playing right now?". The two are
separate vocabularies and must not be mixed.

`CaptureStatusPresentation` in `PresenceFMCore` is the source of truth for
capture wording, symbols, and tone. Both apps read `status.title`,
`status.symbol`, and `action.buttonTitle` from it; each app maps only
`status.tone` onto its own palette. Neither app may restate these in a local
`switch` — that is how the same action came to read "Retry Queue" on iPhone and
"Review Queue" on the Mac.

| Status | Pill title | Tone | Meaning |
| --- | --- | --- | --- |
| `detecting` | Listening | active | Watching for playback; idleness here is normal. |
| `progressing` | In progress | active | Accumulating listening time toward the threshold. |
| `queued` | Queued | paused | Eligible and stored locally, awaiting submission. |
| `submitted` | Scrobbled | positive | Accepted by Last.fm. |
| `excluded` | Not eligible | neutral | Will not scrobble by design; not a failure. |
| `privateMode` | Private Mode | paused | Detected but deliberately not shared. |
| `needsAttention` | Needs attention | critical | Stalled until the person acts. |

Tone carries the judgment so palettes stay app-local. `critical` is the only
tone that means a person must intervene; `status.needsPersonAction` is derived
from it rather than listed separately.

### Capture recovery actions

| Action | Button title | macOS | iOS |
| --- | --- | --- | --- |
| `grantPlaybackPermission` | Grant Permission | Automation settings | Prompts for Music access |
| `reconnectLastFM` | Reconnect Last.fm | Settings → Integrations | Last.fm authorization |
| `retryQueue` | Review Queue | Opens Pending Plays | Drains the local queue |
| `recheckNow` | Check Again | Refreshes integrations | Re-scans recently played music |
| `disablePrivateMode` | End Private Mode | Ends Private Mode | Ends Private Mode |
| `openSettings` | Open Settings | Settings → Integrations | Opens iOS Settings for the app |

`recheckNow` exists so "re-scan now" is not expressed as `openSettings`. Offer
`openSettings` on iOS only where the fix genuinely lives in iOS Settings — for
example once Music access has been denied, since `MusicAuthorization.request()`
will not prompt again.
