# Contributing

PresenceFM requires Swift 6.2, Xcode 26 or later, and targets macOS 15 or later.

1. Create a focused branch.
2. Run `swift test` before submitting a pull request.
3. Do not commit application credentials, user tokens, generated app bundles, or diagnostics containing personal data.
4. Describe behavior changes and manual integration testing in the pull request.

New playback and service integrations should conform to the provider protocols in the domain layer and remain independently testable.

## Planning changes

Use `PLAN.md` for upcoming outcomes and release gates, and `CHANGELOG.md` for
user-visible changes that have already been implemented. When a pull request
changes scope or completes a planned item, update the plan in the same pull
request so it remains useful to someone who only pulls the repository.

## Releases

Tags matching `v*` build a draft GitHub release. The Discord application ID has a public bundled default and does not require a repository secret.

The workflow creates an ad-hoc signed draft and requires no Apple Developer secrets. This is the expected free-account release path; verify the documented Control-click first-launch flow before publishing it.
