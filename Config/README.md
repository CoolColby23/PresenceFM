# Local iOS configuration

PresenceFM's iOS companion is installed from Xcode and uses credentials owned by the person building it. No shared credentials or signing identity are committed.

1. Copy `Local.xcconfig.example` to `Local.xcconfig` and enter your Apple personal-team ID and a unique bundle identifier.
2. Open `PresenceFM.xcworkspace`, select the **PresenceFMiOS** scheme, and choose a physical iPhone.
3. Confirm Signing & Capabilities resolves with automatic signing, then run the app.
4. During onboarding, create or enter your Last.fm API application credentials and connect your account. Use `https://presence-fm.vercel.app/lastfm-callback.html` as its callback URL; it immediately hands the short-lived token back to the app through `presencefm://lastfm-auth`.

A free Apple ID can install the default local-only build on a personally owned iPhone. It intentionally omits CloudKit and push-notification entitlements. The provisioning profile normally expires after seven days, at which point the app must be installed again from Xcode.

Cross-device CloudKit coordination is optional and requires appropriate paid-program capabilities, a private container, and an entitlement-enabled build configuration.

Last.fm credentials and session tokens are stored in the device Keychain and are not compiled into the default binary. The ignored signing configuration and any CloudKit identifiers must never be committed.

For simulator-only UI work, pass temporary values through `xcodebuild` build settings. Apple Music playback and background capture must be validated on a physical device.
