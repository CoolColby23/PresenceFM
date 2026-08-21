# PresenceFM Build Week demo script

Target length: **2:35–2:50**. The public YouTube upload must stay under three
minutes and include spoken coverage of the project, Codex, and GPT-5.6.

## 0:00–0:20 — problem and promise

Show the desktop and menu-bar icon.

> Music presence is fragmented across players, Discord, Last.fm, and separate
> stats tools. PresenceFM brings those pieces into one private-by-default native
> Mac app with no account or backend.

## 0:20–0:55 — live product tour

Show **Now Playing**, artwork/progress, and the service rows. Briefly open the
menu-bar panel.

> PresenceFM detects Apple Music, Spotify, YouTube Music through YTMDesktop, and
> best-effort TIDAL playback. It can publish configurable Discord Rich Presence,
> apply Last.fm's listening threshold, and retain failed scrobbles safely for
> retry. Apple Music Radio works across Now Playing, Discord, local insights,
> and Last.fm, with a 30-second observed fallback when radio duration is unknown.

## 0:55–1:25 — credential-free judge path

Launch with `swift run PresenceFM --demo`, or select **Start Demo Playback** on
the empty Now Playing dashboard.

> For judging, I added deterministic demo playback that enters the real
> production session pipeline. It needs no music or service account. The banner
> makes the safety boundary explicit: synthetic tracks can populate local
> history, but Discord and Last.fm publishing are blocked.

## 1:25–1:55 — local insights and privacy

Open **Listening History** with completed demo listens already available. Show a
period picker, top tracks/platforms, then Private Mode.

> History and insights are calculated only on this Mac. There is no analytics
> backend. Private Mode pauses external sharing, backups exclude credentials,
> and diagnostics redact secrets and local user paths.

## 1:55–2:25 — Codex and GPT-5.6

Show the repository, `DemoPlayback.swift`, its tests, and a terminal with the
passing test summary.

> I used Codex with GPT-5.6 to audit the existing architecture against the live
> Build Week requirements, identify credential-dependent judging as the main
> gap, implement demo playback inside the real provider pipeline, add publication
> safety gates and deterministic tests, and prepare the release and submission
> documentation. The model accelerated engineering without adding an AI runtime
> dependency that would weaken the product's local-first design.

## 2:25–2:45 — close

Return to the main dashboard and show the app plus menu-bar panel.

> PresenceFM makes listening presence coherent, recoverable, and private across
> the services people already use. The repository includes one-command tests,
> release packaging, and a no-credentials judge path.

## Recording checklist

- Keep the final public YouTube video under 3:00.
- Record at 1080p or higher with readable system text.
- Include voiceover; music-only or silent captions do not meet the requirement.
- Say both “Codex” and “GPT-5.6” and explain their concrete contribution.
- Remove typing, build waits, permission prompts, and loading screens.
- Confirm no username, credential, notification, or private listening data is visible.
- Use the final public YouTube URL in the Devpost project before submission.
