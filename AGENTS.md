# Facteur Agent Entry Point

All coding agents must read [CLAUDE.md](CLAUDE.md) before changing the
repository. It contains the project's workflow, safety rules, test commands,
and the rule that pull requests target `main`, never `staging`.

## Active Release Handoff

The iOS/App Store release is not ready for signing or submission yet.

Before doing any iOS, Codemagic, TestFlight, App Store Connect, bundle ID,
signing, or provisioning work, read:

- [iOS/App Store release handoff](docs/handoffs/handoff-ios-app-store-release.md)
- [Codemagic iOS release guide](docs/codemagic-ios-release.md)

The handoff is the source of truth for:

- facts recovered from the May 27, 2026 agent sessions;
- facts re-verified in the canonical checkout on June 8, 2026;
- unresolved engineering blockers;
- actions that require the product owner in Apple/Codemagic web interfaces;
- actions agents must complete and verify before asking the product owner to
  configure signing or upload a build.

Do not treat historical worktree paths from old conversations as canonical.
The canonical repository is the checkout containing this file, and the Flutter
application is at `apps/mobile`.
