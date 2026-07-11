# Contributing

PresenceFM requires Swift 6.2, Xcode 26 or later, and targets macOS 15 or later.

1. Create a focused branch.
2. Run `swift test` before submitting a pull request.
3. Do not commit application credentials, user tokens, generated app bundles, or diagnostics containing personal data.
4. Describe behavior changes and manual integration testing in the pull request.

New playback and service integrations should conform to the provider protocols in the domain layer and remain independently testable.
