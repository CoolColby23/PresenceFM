# PresenceFM Brand Guide

**Tagline:** Your music, present.

PresenceFM makes the music someone is hearing feel alive elsewhere. Its split portal and crossing signal express movement between Apple Music, Discord, and listening history without borrowing their visual languages.

## Logo system

- Use the full-color symbol whenever color is available. Use the mono master for the macOS menu bar, one-color printing, or accessibility contexts.
- Clear space is one quarter of the symbol width on every side. Never place type or interface chrome inside it.
- Minimum sizes: 16 px for the simplified mono symbol, 24 px for the color symbol, and 180 px wide for the full lockup with tagline.
- At 16–20 px, use the native SwiftUI mark or mono SVG. Remove the tagline below 180 px.
- Do not rotate, outline, add effects, recolor individual strokes, alter the waveform, or place the full-color mark on a busy image.

## Color

| Role | Hex | Use |
| --- | --- | --- |
| Electric Blue | `#1F66FF` | Primary actions and identity |
| Signal Cyan | `#14D9FF` | Gradient entry and live state |
| Portal Violet | `#7D33FF` | Gradient bridge |
| Social Magenta | `#F229B8` | Gradient exit and sparing emphasis |
| Pulse Coral | `#FF6E59` | Rare warm highlight |
| Night | `#07142F` | Dark brand background |
| Ink | `#0B1020` | Light-mode text |
| Cloud | `#F7F9FF` | Dark-mode text / light background |
| Slate | `#4D5873` | Light-mode secondary text |
| Mist | `#AEB9D4` | Dark-mode secondary text |

The signature gradient runs cyan → blue → violet → magenta, left to right. Coral may appear only at the far edge of large gradients. Never use a gradient for body text or status meaning.

Status colors remain semantic and independent of the brand gradient: success `#248A3D`, warning `#B85C00`, error `#C82232`, and neutral `#667085`. Pair every status color with text or an icon.

## Typography

- **SF Pro Display:** product name, titles, and short campaign headlines; prefer bold with tight tracking.
- **SF Pro Text:** interface and body copy; use native Dynamic Type styles in the app.
- **SF Mono:** diagnostics, identifiers, and technical values only.
- Recommended marketing hierarchy: 48/52 bold headline, 22/30 regular deck, 17/26 body, 13/18 medium label.

## Imagery and motion

Favor deep spatial fields, crisp luminous signals, album-color reflections, and subtle portal/ripple motifs. Avoid generic equalizers, headphones, vinyl nostalgia, faux audio hardware, or imagery that resembles partner-service branding. Motion should travel left to right and settle quickly; private mode interrupts the outgoing half of the signal.

## Voice

PresenceFM is energetic, direct, transparent, and never performative about privacy.

Messaging pillars:

1. **Live presence:** What you play can appear where your friends are.
2. **Continuous history:** Qualified listens reach Last.fm reliably, even after brief interruptions.
3. **Visible control:** Sharing starts deliberately and private mode is always close.

Write short, active sentences. Say exactly what is shared and where. Prefer “Go Private” to vague security language. Avoid “always watching,” “broadcast everything,” technical protocol language, and claims that imply affiliation with Apple, Discord, or Last.fm.

## Ready-to-use copy

- Short description: “Share what’s playing in Apple Music on Discord and keep your Last.fm history in sync—from one private-by-default Mac app.”
- Launch headline: “Your music, present.”
- Launch deck: “PresenceFM carries the track you’re playing into Discord and Last.fm, with privacy controls always within reach.”
- Social: “Now playing, now present. PresenceFM connects Apple Music to Discord Rich Presence and Last.fm.”
- Onboarding welcome: “Bring your music into the moment.”
- Empty state: “Nothing playing yet. Start a song in Apple Music and PresenceFM will pick it up.”
- Private confirmation: “You’re private. Discord presence is cleared and Last.fm updates are paused.”

## Accessibility

Use `#0B1020` on `#F7F9FF` and `#F7F9FF` on `#07142F` for primary text. Slate is approved on Cloud for normal text; Mist is approved on Night. Do not place text directly on the signature gradient unless it is large white display text over the darkest blue region. Preserve labels alongside color, respect Reduce Motion, and provide the product name as accessible text wherever the mark is meaningful.
