# PresenceFM Brand Guide

**Tagline:** Your music, present.

PresenceFM makes the music someone is hearing feel alive elsewhere. The mark is a single spinning disc — the most literal, universal symbol of "something is playing" — kept deliberately quiet so the product, not the logo, does the talking.

## What changed in this refresh

The previous mark combined a portal arc and a waveform in one gradient shape. It read as busy at small sizes and didn't hold up in the macOS menu bar. This refresh reduces the identity to one shape: **a disc with a center hole**, like a CD. Everything else in the system — color, type, motion, voice — now exists to support that one shape rather than compete with it.

## Logo system

- The mark is a disc: an outer ring with a small center hole, a thin edge outline, and one soft highlight arc suggesting a reflective surface. Nothing else.
- Use the **two-tone color disc** (Signal Cyan → Electric Blue) wherever color is available — app icon, marketing, light or dark UI.
- Use the **mono disc** (single flat color, no highlight) for the macOS menu bar, favicons below 24 px, one-color printing, and any context where a gradient would be illegible.
- Clear space is half the disc's diameter on every side. Never place type, chrome, or other marks inside the hole or touching the ring.
- Minimum sizes: 16 px for the mono disc, 24 px for the color disc, 160 px wide for the full lockup with wordmark. Drop the tagline below 160 px, and drop the wordmark entirely below 24 px — show the disc alone.
- Do not: add a second gradient stop, outline the disc in a color other than white/night, distort it into an ellipse, add spokes or a waveform back into the mark, drop a shadow behind it, or place the color disc on a busy photographic background. The disc should always read as one clean shape at a glance.

## Color

| Role | Hex | Use |
| --- | --- | --- |
| Electric Blue | `#1F66FF` | Primary actions, disc gradient (exit), identity |
| Signal Cyan | `#14D9FF` | Disc gradient (entry), live state |
| Night | `#07142F` | Dark brand background |
| Ink | `#0B1020` | Light-mode text |
| Cloud | `#F7F9FF` | Dark-mode text / light background |
| Slate | `#4D5873` | Light-mode secondary text |
| Mist | `#AEB9D4` | Dark-mode secondary text |

**The disc gradient is Cyan → Blue only**, applied diagonally across the disc face and nowhere else — not on buttons, text, or backgrounds. This is the one piece of color richness the brand allows itself; keeping it confined to the disc is what keeps the rest of the system calm.

Portal Violet (`#7D33FF`), Social Magenta (`#F229B8`), and Pulse Coral (`#FF6E59`) are retired from the core identity. If a marketing surface needs a rare warm accent, use Pulse Coral sparingly and never as part of the disc or logo itself.

Status colors remain semantic and independent of brand color: success `#248A3D`, warning `#B85C00`, error `#C82232`, neutral `#667085`. Pair every status color with text or an icon, never color alone.

## Typography

- **SF Pro Display:** product name, headlines, short campaign copy. Bold, tight tracking.
- **SF Pro Text:** interface and body copy. Use native Dynamic Type styles in the app.
- **SF Mono:** diagnostics, identifiers, and technical values only.
- Marketing hierarchy: 48/52 bold headline, 22/30 regular deck, 17/26 body, 13/18 medium label.

## Imagery and motion

Favor calm, deep-field backgrounds with the disc as the only bright object in frame. The disc may rotate slowly and continuously to suggest playback — this is the one motion signature of the brand. Keep rotation slow (10–15 seconds per revolution), never sync it to music tempo, and always respect Reduce Motion by freezing it in place.

Avoid generic equalizers, headphones, vinyl-record nostalgia, faux hardware, waveforms, or any imagery that resembles Apple, Discord, or Last.fm's own visual language. One disc, one motion, no clutter.

## Voice

PresenceFM is energetic, direct, transparent, and never performative about privacy. This hasn't changed — only the visual system has become quieter to match.

Messaging pillars:

1. **Live presence:** What you play can appear where your friends are.
2. **Continuous history:** Qualified listens reach Last.fm reliably, even after brief interruptions.
3. **Visible control:** Sharing starts deliberately and private mode is always close.

Write short, active sentences. Say exactly what is shared and where. Prefer "Go Private" to vague security language. Avoid "always watching," "broadcast everything," technical protocol language, and claims that imply affiliation with Apple, Discord, or Last.fm.

## Ready-to-use copy

- Short description: "Share what's playing in Apple Music on Discord and keep your Last.fm history in sync—from one private-by-default Mac app."
- Launch headline: "Your music, present."
- Launch deck: "PresenceFM carries the track you're playing into Discord and Last.fm, with privacy controls always within reach."
- Social: "Now playing, now present. PresenceFM connects Apple Music to Discord Rich Presence and Last.fm."
- Onboarding welcome: "Bring your music into the moment."
- Empty state: "Nothing playing yet. Start a song in Apple Music and PresenceFM will pick it up."
- Private confirmation: "You're private. Discord presence is cleared and Last.fm updates are paused."

## Accessibility

Use `#0B1020` on `#F7F9FF` and `#F7F9FF` on `#07142F` for primary text. Slate is approved on Cloud for normal text; Mist is approved on Night. Do not place text on the disc gradient itself. Always provide "PresenceFM" as accessible text wherever the disc mark appears alone. Preserve the mono disc's silhouette (ring + hole) as the accessible shape at every size — it must remain identifiable without color.
