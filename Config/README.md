# Local iOS configuration

PresenceFM's iOS companion is installed from Xcode and uses credentials owned by the person building it. No shared credentials or signing identity are committed.

1. Create a Last.fm API application at <https://www.last.fm/api/account/create> and set its callback URL to `presencefm://lastfm-auth`.
2. Copy `Local.xcconfig.example` to `Local.xcconfig` and replace every placeholder.
3. Create an iCloud container in the Apple Developer portal. Assign the same container to the macOS and iOS app identifiers.
4. Open `PresenceFM.xcworkspace`, select the **PresenceFMiOS** scheme, and choose a physical iPhone.
5. Confirm Signing & Capabilities resolves Music, Media Library, Keychain, CloudKit, Background Fetch, and notifications.
6. Run the app, grant Music access, and connect Last.fm from Settings.

The shared secret is compiled into your personal binary and can be extracted from it. Do not distribute that binary. The ignored configuration, Last.fm session token, and CloudKit credentials must never be committed.

For simulator-only UI work, pass temporary values through `xcodebuild` build settings. Apple Music playback and background capture must be validated on a physical device.
