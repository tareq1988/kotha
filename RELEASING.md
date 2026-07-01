# Releasing Kotha

Kotha ships auto-updates via [Sparkle](https://sparkle-project.org). Existing users
get new versions automatically from the appcast on GitHub. Cutting a release is one
command.

## TL;DR

```bash
./release.sh 1.2                       # version only
./release.sh 1.2 "Fix paste; faster startup"   # with release notes
```

That's it. The script does everything below and prints the release URL.

## What `release.sh` does

1. **Pre-flight** — verifies you're on `main`, the working tree is clean, `main`
   isn't behind origin, `gh` is authenticated, and the tag/release/appcast entry
   don't already exist. Bails out (reverting any changes) if not.
2. **Bumps versions** in `project.yml`:
   - `MARKETING_VERSION` → the version you passed (user-facing, e.g. `1.2`).
   - `CURRENT_PROJECT_VERSION` → auto-incremented by 1 (the build number Sparkle
     compares — **must** increase every release).
3. **Builds** (`xcodegen generate` + `build.sh`, re-signed with the stable identity)
   and verifies the built app actually reports the expected version/build.
4. **Packages** `dist/Kotha-<version>.zip` with `ditto` (preserves the signature).
5. **EdDSA-signs** the zip with Sparkle's `sign_update` (private key lives in your
   login Keychain) and prepends an `<item>` to `appcast.xml`.
6. **Commits** (`Release <version>`), **tags** `v<version>`, and **pushes** both.
7. **Creates the GitHub release** and uploads the zip as the asset.

## Versioning

| Field | Example | Role |
|-------|---------|------|
| `MARKETING_VERSION` | `1.2` | What users see. Choose it: `./release.sh 1.2`. |
| `CURRENT_PROJECT_VERSION` | `3` | Build number Sparkle uses to decide "newer". Auto-incremented. |

Both are wired into `Info.plist` via `$(…)` build settings, so they always match
the binary. Never hand-edit them for a release — let the script do it.

## How users receive it

- Kotha checks the appcast (`SUFeedURL` in Info.plist) on launch and daily, and via
  **Check for Updates…** in the menu.
- The download is verified against the embedded `SUPublicEDKey` before installing.
- Only builds **≥ 1.1** self-update (1.0 predates Sparkle and used a different bundle id).

## Prerequisites (one-time)

- `brew install xcodegen gh` and `gh auth login`.
- `./setup-signing.sh` once (stable code-signing identity; also lets permissions
  persist across builds).
- A Sparkle EdDSA key in your Keychain. One already exists; running
  `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` prints the
  existing public key. The matching `SUPublicEDKey` is in `project.yml` / `Info.plist`.

## If it fails partway

- **Before the commit** (build/sign error): the script reverts the version bump, so
  just fix the issue and re-run.
- **After push, release upload failed:** the tag/commit are already public; finish
  with the exact `gh release create … --verify-tag` command the script prints.

## Not yet done

- **Notarization.** The app is self-signed, not notarized, so first-time installers
  hit Gatekeeper (right-click → Open). Auto-updates still verify via EdDSA. Adding a
  Developer ID + notarization to `build.sh` would remove the first-launch warning.
