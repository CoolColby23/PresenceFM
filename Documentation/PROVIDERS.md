# Playback Provider Matrix

| Provider | Metadata surface | Permission/setup | Known limitation |
| --- | --- | --- | --- |
| Apple Music | AppleScript | macOS Automation | Permission loss yields low-confidence state and recovery guidance. |
| Spotify | AppleScript | Spotify Desktop running | Spotify must expose a valid current-track response. |
| YouTube Music | YTMDesktop Companion Server v1 | Local server and companion authorization | Requires YTMDesktop 2; live videos are never scrobbled. |
| TIDAL | macOS MediaRemote Now Playing | TIDAL Desktop running | Best effort; MediaRemote is not a public TIDAL API and may change with macOS. |

Users can disable providers individually. Selection keeps the active playing provider; otherwise the stable priority is Apple Music, Spotify, YouTube Music, then TIDAL. A failing provider does not mask valid playback from another provider. TIDAL is queried only when a higher-priority provider is not playing.
