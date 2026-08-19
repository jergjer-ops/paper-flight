# Mobile (Android) build pipeline

Paper Flight is a single-page game. The web version lives in the repo root
(`index.html`). The Android app (Capacitor + WebView) must not drift from it,
so it is **generated** from the web version — never edited by hand.

## Layout

- `android/` — Capacitor project (sources only; build artifacts are gitignored)
- `scripts/mobile-sync.sh` — copies `index.html` + shared assets from repo root
  into `android/www`, strips ad SDKs (Playgama / CrazyGames / YT Playables),
  applies the strict WebView CSP, and verifies JS syntax
- `scripts/mobile-release.sh` — sync + Capacitor sync + signed release build +
  `adb install -r`

## Release

```sh
./scripts/mobile-release.sh
```

Requirements: `adb` with a connected device, `node`, `npm`, Android SDK, and
the release keystore (see `android/android/app/build.gradle` — it reads
`PF_STORE_PASSWORD` / `PF_KEY_PASSWORD` from the environment; on this machine
`mobile-release.sh` pulls them from the macOS Keychain automatically).

## Signing

The keystore is **not** in the repository. `android/android/app/build.gradle`
reads credentials from environment variables:
`PF_KEYSTORE`, `PF_STORE_PASSWORD`, `PF_KEY_ALIAS`, `PF_KEY_PASSWORD`.
