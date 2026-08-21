# PresenceFM website

The marketing site is intentionally dependency-free. It uses the canonical assets in the repository's top-level `brand/` directory.

Pushes to `main` that change `website/` are verified and deployed through the
GitHub Pages workflow. Enable **GitHub Actions** as the Pages source in the
repository settings before the first deployment.

## Preview locally

From the repository root:

```sh
python3 -m http.server 4173
```

Then open `http://localhost:4173/website/`.

Run the same integrity check used by CI with:

```sh
./scripts/verify-website.sh
```

## Structure

- `index.html` — semantic page content
- `styles.css` — responsive brand system and layout
- `script.js` — responsive mobile-navigation behavior
- `assets/` — website-specific raster assets
