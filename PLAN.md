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

## Now — ship 0.4.0

Goal: stabilize and publish the integration and distribution work already in
progress, including the requested playback providers.

- [x] Add Spotify playback, configurable Discord presence, stricter Last.fm
  response validation, structured issue forms, and branded DMG packaging.
- [x] Add authenticated YTMDesktop Companion Server v1 playback and TIDAL
  playback through the macOS Now Playing metadata surface, both with safe
  unavailable-state behavior.
- [x] Add pull-request CI for tests, a release build, `git diff --check`, and a
  packaging smoke test; keep tagged release publishing as a separate workflow.
- [x] Add deterministic tests for Spotify state transitions, source switching,
  provider loss/recovery, Discord configuration rendering, and malformed Last.fm
  responses.
- [ ] Run the account- and permission-dependent checks in
  `Documentation/MANUAL-QA.md`, including a clean installation and migration from
  preserved 0.3 data, and record the result in a new 0.4 QA record.
- [-] Verify the local release-candidate DMG, checksum, bundle metadata,
  signature, resources, and first-launch instructions. The tagged workflow and
  downloaded GitHub Release artifact remain intentionally gated on manual QA.

### 0.4.0 release gates

A release is ready when all of the following are true:

- `swift test` and `swift build -c release` pass.
- The packaged app launches and contains the intended version, entitlements,
  resources, and privacy usage strings.
- Every manual QA item passes or has an explicitly documented, accepted risk.
- Diagnostics, notifications, exported issue text, and logs expose no secrets or
  unnecessary personal data.
- `CHANGELOG.md`, `README.md`, and the website agree on supported playback
  providers and shipped behavior.
- The release DMG is ad-hoc signed, checksummed, and tested after download;
  the lack of notarization is documented as an accepted free-distribution risk.

## Next — earn the 1.0 stability contract

Goal: make the existing product predictable, recoverable, accessible, and safe
to evolve. Version 1.0 is a stability milestone, not a feature-count milestone.

### Candidate 0.5.0 — reliability and testability

- [-] Expand deterministic coverage for playback transitions, seeking,
  cross-provider switching, scrobble-threshold boundaries, queue retries,
  retention, corrupted data, and every supported migration path.
- [x] Introduce injectable clocks and service fakes where time or external app
  state currently makes tests fragile.
- [x] Add structured, privacy-redacted diagnostics that make Music, Discord, and
  Last.fm failures easier to distinguish and export for a bug report.
- [x] Document the local persistence schema and establish an explicit migration
  policy, fixture set, rollback behavior, and backup expectations before adding
  more stored insight data.
- [x] Define bounded retry, timeout, cache, polling, and data-retention behavior
  for every integration, then test the failure paths.

### Candidate 0.6.0 — product and accessibility polish

- [ ] Add accessibility and keyboard-navigation checks for onboarding,
  settings, menu-bar controls, queue recovery, and listening-history filters;
  verify VoiceOver labels, focus order, reduced motion, contrast, and Dynamic
  Type equivalents available on macOS.
- [ ] Make integration status and recovery language consistent across the menu,
  dashboard, settings, notifications, and diagnostics.
- [x] Review first-run and single-integration onboarding so Discord-only,
  Last.fm-only, Apple Music-only, and Spotify-only setups have clear paths.
- [ ] Measure polling, artwork caching, and dashboard update costs during long
  sessions; set and document practical idle/playing CPU, memory, launch-time,
  and energy budgets.
- [x] Freeze the CSV export columns and meanings as a documented v1 format.

## v1.0.0 release gates

Version 1.0.0 is ready only when all of the following are true:

- [ ] The supported provider matrix is explicit. Each provider passes play,
  pause, seek, skip, source-switch, app-quit, permission-loss, sleep/wake, and
  relaunch tests, or its known limitation is documented before installation.
- [ ] Discord presence and Last.fm now-playing/scrobbling recover correctly from
  offline operation, revoked credentials, service restarts, rate limits, and
  malformed responses without duplicates or lost eligible scrobbles.
- [ ] Every persistence version from the earliest supported public release has
  a tested forward migration; corrupt or partial state fails safely with a
  documented recovery path.
- [ ] Private Mode prevents all external publishing, expires reliably across
  sleep/relaunch, and local-history behavior is stated plainly in the UI and
  privacy documentation.
- [ ] A full keyboard and VoiceOver pass has no release-blocking issue, and the
  app remains usable with increased contrast and reduced motion.
- [ ] Clean install, upgrade, launch at login, permission denial/recovery, and
  uninstall-data guidance pass on the oldest and newest supported macOS
  versions on both Intel and Apple silicon where the OS supports them.
- [ ] A four-hour mixed-playback soak test stays within the documented resource
  budgets and produces no duplicate submissions, unbounded queue/cache growth,
  or stale presence.
- [ ] CI protects every pull request; the tagged workflow reproducibly creates a
  launchable DMG with correct versioning, checksum, resources, entitlements,
  privacy strings, and release notes.
- [ ] Security, privacy, support, contribution, export-schema, persistence, and
  troubleshooting documentation match the shipped app, and diagnostics have
  been reviewed for credential and personal-data leakage.
- [ ] All automated tests pass and every manual QA item is recorded as passed or
  as an explicitly accepted, documented risk. There are no open P0/P1 defects
  and no unresolved data-loss, privacy, duplicate-scrobble, or stuck-presence
  defect.

## Later — product improvements

- [x] Make listening-history summaries easier to compare across useful time
  periods without weakening the local-only privacy model.
- [x] Add clearer integration health history and recovery guidance without
  collecting telemetry.
- [ ] Evaluate additional metadata and presence controls only when they remain
  understandable, optional, and locally managed.

## Exploring

These are candidates, not commitments.

- [x] Versioned PresenceFM backup/restore for local history, queue data, and non-secret settings.
- Optional shortcuts or system actions for Private Mode and common recovery
  tasks.
- Localization after the interface copy and accessibility labels stabilize.
- A contributor-friendly mock playback mode for testing without changing a real
  Apple Music session.
- Developer ID signing and notarization if sustainable funding or sponsorship
  becomes available; this is not a v1 blocker while the current risk is clearly
  documented.

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
- [x] Branded DMG distribution, repository issue forms and labels, automatic PR
  size labels, platform-aware Discord customization, and Apple Music, Spotify,
  YTMDesktop, and TIDAL playback providers implemented for 0.4.0.
- [x] DMG drag guidance and polished Discord presentation with artwork context,
  platform badges, configurable text, links, and track-progress timestamps.
- [x] Last.fm authorization-token separation, signed-request coverage, accepted
  response validation, and permanent handling for rejected scrobbles.

## Planning principles

- Privacy remains the default: no PresenceFM account, backend, analytics, or
  uploaded listening history.
- Playback monitoring must remain useful when either optional integration is
  disabled or unavailable.
- Failed network work must be bounded, deduplicated, recoverable, and safe to
  retry.
- New behavior should be testable without live credentials whenever practical.
- Compatibility and accessibility are release requirements, not follow-up work.
