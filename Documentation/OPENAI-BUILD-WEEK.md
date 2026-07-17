# OpenAI Build Week — PresenceFM

## Submission snapshot

- **Category:** Apps for Your Life
- **Project:** PresenceFM
- **Repository:** https://github.com/CoolColby23/PresenceFM
- **Supported platform:** macOS 15 or later
- **License:** MIT

## The problem

Music listeners often use one player, Discord for social presence, Last.fm for
long-term history, and another tool for personal insights. Each integration has
different failure modes and privacy implications. PresenceFM turns that
fragmented workflow into one native, private-by-default Mac app with no account,
backend, analytics, or uploaded listening-history database.

## What PresenceFM does

PresenceFM detects playback from Apple Music, Spotify, YouTube Music through
YTMDesktop, and best-effort TIDAL metadata. It can publish a configurable Discord
Rich Presence, update and scrobble to Last.fm, and maintain searchable local
history and listening insights. Private Mode pauses external publishing. A
bounded retry queue, versioned persistence, recovery backups, and privacy-redacted
diagnostics make the integrations recoverable rather than fragile.

## Judge path — no accounts required

1. On macOS 15 or later, clone the repository.
2. Run `swift test` and then `swift run PresenceFM --demo`.
3. The demo launch skips onboarding for that run without changing its saved
   completion state or enabling an integration.
4. On **Now Playing**, watch a simulated track move through the same
   playback-session and eligibility pipeline used for live music.
5. Leave the demo running for about one minute, then open **Listening History**
   to inspect locally recorded sample listens, filters, and insights.
6. Select **End Demo** before testing a real music player.

Demo Mode is intentionally ephemeral and defaults off on every launch. While it
is active, PresenceFM clears Discord presence and blocks both Discord and Last.fm
publishing. Demo listens can exercise the local history pipeline but cannot be
queued as Last.fm scrobbles.

For the release-style path, run:

```sh
./scripts/verify-build-week.sh
open PresenceFM.app --args --demo
```

The packaging script uses an available Apple Development identity and otherwise
falls back to ad-hoc signing. PresenceFM is not notarized, so on another Mac the
first launch may require Control-clicking the app and choosing **Open**.

## How Codex and GPT-5.6 were used

Codex with GPT-5.6 was used as an implementation partner for the Build Week
readiness pass:

- Audited the existing SwiftUI, playback-provider, persistence, test, packaging,
  and documentation surfaces against the live Devpost requirements.
- Identified credential-dependent judge testing as the highest-leverage gap.
- Designed and implemented deterministic demo playback inside the existing
  provider/session architecture instead of building a disconnected mock screen.
- Added safety gates so synthetic tracks exercise local state without publishing
  to Discord or Last.fm.
- Added deterministic Swift Testing coverage, judge instructions, submission
  copy, and an under-three-minute demo plan.
- Ran the automated tests and the same release/package verification scripts used
  by CI.

The shipped app does not call an AI model at runtime. GPT-5.6 and Codex were used
to accelerate product engineering, reasoning about integration boundaries,
test design, and release preparation. This preserves PresenceFM's local-first
privacy model and avoids adding an AI dependency where the user problem does not
need one.

## Key engineering decisions

### Exercise the real product path

The judge experience produces normal `PlaybackSnapshot` values. Those snapshots
flow through the same `PlaybackSessionTracker`, eligibility calculations,
SwiftData history, and SwiftUI observation as live providers. This makes the demo
useful as a test surface rather than a visual prop.

### Keep synthetic data safe

Demo Mode is app state, not a saved preference. It starts off after every launch.
External publishing is blocked in the Last.fm now-playing, Last.fm eligibility,
and Discord publication paths. Pending scrobble approval is cleared when the
mode starts.

### Preserve privacy and reliability

PresenceFM does not need a hosted service. Credentials remain in an owner-only
local file, history stays in SwiftData on the Mac, exports are explicit, caches
and queues are bounded, and diagnostics redact common secrets and user paths.

## Architecture at a glance

```text
Music / Spotify / YTMDesktop / TIDAL ─┐
                                      ├─ PlaybackMonitor
Credential-free Demo Mode ────────────┘         │
                                                ▼
                                  PlaybackSessionTracker
                                      │                 │
                                      ▼                 ▼
                              Local SwiftData      Optional services
                              history/insights     Discord + Last.fm
                                      ▲                 ▲
                                      └── demo allowed  └── demo blocked
```

## Verification

- `swift test` covers playback sessions, provider selection, demo sequencing,
  Last.fm transport, Discord payloads, persistence, backup/restore, privacy,
  artwork, insights, and injected-clock scheduling.
- `scripts/package-app.sh` creates the release-mode `.app` bundle.
- `scripts/verify-package.sh` verifies metadata, resources, entitlements, and
  code signing.
- `scripts/verify-website.sh` checks the dependency-free project website.

Manual account-, hardware-, and OS-dependent release checks remain explicitly
tracked in [QA-1.0.0-RC.md](QA-1.0.0-RC.md); they are not represented as
automated passes.

## Final Devpost submission inputs

The Devpost project copy, links, technology list, and thumbnail can be prepared
from the repository. Final challenge submission still requires information that
must come from the entrant:

- A public YouTube demo URL under three minutes with voiceover covering the
  product, Codex, and GPT-5.6.
- The submitter type and country of residence.
- The `/feedback` Codex Session ID for the session where most core work happened.
- A final human review of the project description and video.

Use **Apps for Your Life** as the category. Do not leave the final challenge
entry as a draft. The submission deadline is **July 21, 2026 at 5:00 PM Pacific
Time** (`2026-07-22T00:00:00Z`). Follow the exact entrant-only sequence in
[BUILD-WEEK-FINAL-SUBMISSION.md](BUILD-WEEK-FINAL-SUBMISSION.md).
