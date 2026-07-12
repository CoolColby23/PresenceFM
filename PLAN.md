# PresenceFM Project Plan

This file is the repository's lightweight source of truth for planned work. It
describes outcomes rather than promising dates. Completed user-visible changes
belong in `CHANGELOG.md`, while detailed release verification belongs in
`Documentation/`.

## How to update this plan

- Keep **Now** limited to the work required for the next releasable milestone.
- Move an item to **Completed** only after its implementation and relevant tests
  or manual QA are complete.
- Add a link to an issue or pull request when one exists, but keep enough context
  here for the plan to remain useful offline.
- Mark uncertain ideas as **Exploring**. Moving one into **Next** is the decision
  to pursue it; ordering inside a section is not a priority guarantee.
- Review this file whenever a release is tagged or its scope changes.

Status notation: `[ ]` planned, `[-]` in progress or partially verified, and
`[x]` complete.

## Now — ship 0.3.0

Goal: publish a trustworthy release of the new listening-history and rich
now-playing experience.

- [-] Complete the account- and permission-dependent checks in
  `Documentation/MANUAL-QA.md`; record the result in
  `Documentation/QA-0.3.0.md`.
- [ ] Verify Discord publishing, clearing, reconnection, and timed Private Mode
  across sleep and wake.
- [ ] Verify Last.fm authorization, exactly-once scrobbling, offline recovery,
  revoked-session recovery, and queue controls with a test account.
- [ ] Exercise clean-install Gatekeeper and Apple Music Automation permission
  denial/recovery.
- [ ] Verify CSV export, retention pruning, history deletion, and migration from
  preserved 0.2 data.
- [ ] Validate launch at login and the supported macOS range, with special
  attention to macOS 15 compatibility and macOS 26 visual treatment.
- [-] Produce an ad-hoc signed release artifact, verify its checksum and
  documented Gatekeeper flow, and publish the release notes.

### 0.3.0 release gates

A release is ready when all of the following are true:

- `swift test` and `swift build -c release` pass.
- The packaged app launches and contains the intended version, entitlements,
  resources, and privacy usage strings.
- Every manual QA item passes or has an explicitly documented, accepted risk.
- Diagnostics, notifications, exported issue text, and logs expose no secrets or
  unnecessary personal data.
- `CHANGELOG.md`, `README.md`, and the website describe the shipped behavior.
- The release archive is ad-hoc signed, checksummed, and tested after download;
  the lack of notarization is documented as an accepted free-distribution risk.

## Next — strengthen reliability and maintainability

- [ ] Add CI for pull requests that runs tests, a release build, and repository
  hygiene checks independently of the tagged-release workflow.
- [ ] Expand deterministic coverage for playback transitions, seeking,
  scrobble-threshold boundaries, queue retries, retention, and migrations.
- [ ] Introduce injectable clocks and service fakes where time or external app
  state currently makes tests fragile.
- [ ] Add structured, privacy-redacted diagnostics that make Music, Discord, and
  Last.fm failures easier to distinguish.
- [ ] Document the local persistence schema and establish an explicit migration
  policy before adding more stored insight data.
- [ ] Add accessibility and keyboard-navigation checks for onboarding,
  settings, queue recovery, and listening-history filters.
- [ ] Measure polling, artwork caching, and dashboard update costs during long
  sessions; set practical CPU and memory budgets.

## Later — product improvements

- [ ] Make listening-history summaries easier to compare across useful time
  periods without weakening the local-only privacy model.
- [ ] Improve export portability with a documented schema and stable column
  meanings.
- [ ] Add clearer integration health history and recovery guidance without
  collecting telemetry.
- [ ] Evaluate additional metadata and presence controls only when they remain
  understandable, optional, and locally managed.
- [ ] Streamline onboarding for people who want only Discord or only Last.fm.

## Exploring

These are candidates, not commitments.

- Import and backup/restore for local listening history.
- Optional shortcuts or system actions for Private Mode and common recovery
  tasks.
- Localization after the interface copy and accessibility labels stabilize.
- A contributor-friendly mock playback mode for testing without changing a real
  Apple Music session.

## Completed foundation

- [x] Native Apple Music playback monitoring with local-first operation.
- [x] Optional Discord Rich Presence and Last.fm now-playing/scrobbling.
- [x] Persistent retry queue, Private Mode, onboarding, and diagnostics.
- [x] Local listening history, insights, filters, retention controls, and CSV
  export implemented for 0.3.0.
- [x] Album artwork, playback progress, recovery notifications, and richer
  dashboard/menu-bar presentation implemented for 0.3.0.
- [x] Draft release packaging with ad-hoc signing that requires no paid Apple
  Developer account.

## Planning principles

- Privacy remains the default: no PresenceFM account, backend, analytics, or
  uploaded listening history.
- Playback monitoring must remain useful when either optional integration is
  disabled or unavailable.
- Failed network work must be bounded, deduplicated, recoverable, and safe to
  retry.
- New behavior should be testable without live credentials whenever practical.
- Compatibility and accessibility are release requirements, not follow-up work.
