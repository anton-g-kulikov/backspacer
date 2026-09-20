# Contributing

Thanks for looking. Two kinds of contribution help most:

1. **Bug reports** — open an issue and attach `~/Library/Logs/Backspacer/Backspacer.log`
   (About → *Reveal log*). It names the folders the app measured; trim it if you like.
2. **Catalog entries** — the knowledge in `catalog.json` is the product. A good
   entry answers five questions; the issue and PR templates ask them:
   - **What is it?** The app or tool, and what the folder holds.
   - **Where?** The exact path (or glob). Verified on a real Mac — which macOS,
     which app version?
   - **Which bucket, and why?** `safe` (rebuilt on its own, no cost), `regen`
     (comes back on the next build or install, costs time), `decide` (real data
     — the user chooses), `keep`, or `locked`. Caches an app rebuilds are not
     "your call"; data that can't be regenerated is not "safe".
   - **What brings it back?** The command or action, and what the user loses
     meanwhile (a slow first launch, re-login, lost history…).
   - **Any catch?** Needs the app quit first? Admin? Full Disk Access? Nested in
     another entry?

## Before you open a pull request

- `swift test` and `npm ci && node --test 'Tests/web/logic.test.js' 'Tests/web/a11y.test.js' 'Tests/web/axe.test.js' 'Tests/web/brand.test.js' 'Tests/web/release.test.js'`
  pass (CI runs exactly these; `npm ci` fetches axe-core and jsdom for the
  rendered accessibility suite — test-only, the app has no dependencies). The Swift suites include the safety gate over
  every catalog path and the schema — a rejected entry is the test telling you
  something. `Tests/test-documentation.md` says what each suite proves.
- To try the app: `BUNDLE_ID=com.antonkulikov.backspacer.dev scripts/build-app.sh && open -n build/Backspacer.app`
  — the `.dev` bundle id keeps it apart from an installed copy (own prefs, own
  Full Disk Access grant).
- Releases are the maintainer's: a `vX.Y.Z` tag builds, notarizes and publishes the
  DMG through GitHub Actions, and the Homebrew tap follows by itself. Don't bump
  versions in a PR.
- One change per PR. Fill in the template; the bucket rationale is what gets
  reviewed most carefully.
- Code changes follow the repo's shape: intent in `Tests/test-documentation.md`,
  a failing test first, docs in the one `_meta/` file that owns the concept.

Every PR is reviewed by the maintainer before merge; CI must be green. An app
that deletes folders doesn't take drive-by merges.

## Terms

The project is distributed under the PolyForm Noncommercial License 1.0.0 (see
`LICENSE`). So that the maintainer can keep distributing Backspacer under that
license and offer commercial licenses, **contributions are made under the
Apache License 2.0**: by submitting a pull request you license your
contribution to the project under Apache-2.0. You keep your copyright. If you
can't agree to that, please open an issue describing the change instead.
