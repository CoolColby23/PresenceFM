# PresenceFM website

The marketing site is intentionally dependency-free. It uses the canonical assets in the repository's top-level `brand/` directory.

## Preview locally

From the repository root:

```sh
python3 -m http.server 4173
```

Then open `http://localhost:4173/website/`.

## Structure

- `index.html` — semantic page content
- `styles.css` — responsive brand system and layout
- `script.js` — mobile navigation, reveal motion, and privacy-demo state
- `assets/` — website-specific raster assets
