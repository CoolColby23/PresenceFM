# PresenceFM desktop widget

`WidgetExtension/PresenceFMWidget.swift` defines a native WidgetKit extension for the small and medium macOS desktop/Notification Center families. It reads a minimal now-playing snapshot, advances finite playback progress from the snapshot timestamp, refreshes on a one-minute timeline, and hides all listening metadata during Private Mode.

The app publishes that snapshot through the `group.fm.presence.PresenceFM` UserDefaults suite and requests timeline reloads only when the track, playback state, privacy state, or 30-second progress bucket changes. This bounds extension refresh traffic while allowing WidgetKit to advance progress locally.

The current SwiftPM release package does not embed the extension. Shipping it requires:

1. An Apple Developer App ID and widget extension App ID.
2. The `group.fm.presence.PresenceFM` app group enabled for both identifiers.
3. Provisioning profiles containing that app group.
4. A separately signed `.appex` embedded under `PresenceFM.app/Contents/PlugIns`.
5. Package verification that checks the extension signature, sandbox, app group, timeline loading, Private Mode redaction, and widget-gallery discovery.

Until those signing prerequisites are available, the widget is source-ready and type-checked but remains a release blocker rather than an implied shipped feature.
