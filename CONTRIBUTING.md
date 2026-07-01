# Contributing

## Commit messages — Conventional Commits

This repo uses [Conventional Commits](https://www.conventionalcommits.org).
Every commit's first line must be:

```
<type>(<optional scope>): <description>
```

**Types**

| Type | Use for |
|------|---------|
| `feat` | a new user-facing feature |
| `fix` | a bug fix |
| `perf` | a performance improvement |
| `refactor` | code change that neither fixes a bug nor adds a feature |
| `docs` | documentation only |
| `style` | formatting/whitespace, no code meaning change |
| `test` | adding or fixing tests |
| `build` | build system, packaging, release tooling, dependencies |
| `ci` | CI configuration |
| `chore` | anything else (maintenance) |
| `revert` | reverts a previous commit |

**Scope** (optional) is the area touched, lowercase: `hotkeys`, `cleanup`,
`overview`, `storage`, `release`, `ui`, …

**Breaking changes**: add `!` before the colon, e.g. `feat(storage)!: …`.

**Examples**

```
feat(hotkeys): let users choose the trigger modifier key
fix(cleanup): stop dropping the last word on empty transcript
perf(storage): move JSON writes off the main thread
docs(release): document the release process
build(release): auto-increment the build number in release.sh
```

Keep the description in the imperative mood ("add", not "added") and under ~72 chars.

### Enforcement

A `commit-msg` hook validates the format. Enable it once after cloning:

```bash
git config core.hooksPath .githooks
```

Merge, revert, and `fixup!`/`squash!` commits are allowed through.

## Why it matters here

`release.sh` reads these commits to auto-generate release notes (grouped into
Features / Fixes / Other) since the last tag. Good commit messages → good
changelogs for free. See [RELEASING.md](RELEASING.md).
