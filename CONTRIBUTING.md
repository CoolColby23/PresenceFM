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

| Tag shape | Channel | GitHub | Sparkle appcast |
|-----------|---------|--------|-----------------|
| `v1.1.0` | Production | Draft → publish as Latest | Generated and attached |
| `v1.1.0-beta.1` / `v1.1.0-rc.1` | Pre-release | Draft → publish as Pre-release | Skipped |

`VERSION` must match the tag base (for example tag `v1.1.0-beta.1` requires `VERSION` `1.1.0`).

The workflow creates an ad-hoc signed draft and requires no Apple Developer secrets. This is the expected free-account release path; verify the documented Control-click first-launch flow before publishing it.

### Cut a pre-release

```sh
git checkout main   # or the release branch after merge
git tag v1.1.0-beta.1
git push origin v1.1.0-beta.1
# Review the draft on GitHub, then publish as Pre-release
```

### Cut production

```sh
git tag v1.1.0
git push origin v1.1.0
# Review the draft (includes appcast.xml), then publish as Latest
```
