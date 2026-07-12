# Contributing

PresenceFM requires Swift 6.2, Xcode 26 or later, and targets macOS 15 or later.

1. Create a focused branch.
2. Run `swift test` before submitting a pull request.
3. Do not commit application credentials, user tokens, generated app bundles, or diagnostics containing personal data.
4. Describe behavior changes and manual integration testing in the pull request.

New playback and service integrations should conform to the provider protocols in the domain layer and remain independently testable.

## Releases

Tags matching `v*` build a draft GitHub release. The Discord application ID has a public bundled default and does not require a repository secret.

Signed and notarized releases require these GitHub Actions secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application `.p12`.
- `MACOS_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`.
- `MACOS_SIGNING_IDENTITY`: the full Developer ID Application certificate name.
- `KEYCHAIN_PASSWORD`: an ephemeral CI keychain password.
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`: notarization credentials.

When `MACOS_CERTIFICATE` is absent, the workflow intentionally creates an unsigned draft for testing. Do not publish that draft as a public production release.
