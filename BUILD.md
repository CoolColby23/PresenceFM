# Building & Preview Builds

Local debug build:

```bash
swift build -c debug
```

Run preview packaging script (if present):

```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh
```

CI preview builds are triggered on branches matching `preview/**` and on pull requests to `main`. Preview DMG artifacts are uploaded and attached to a draft release.
