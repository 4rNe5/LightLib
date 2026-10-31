# Contributing to LightLib

Thanks for helping. A few things keep changes easy to review:

- **Start with an issue** for anything beyond a small fix, so we agree on the approach first. Bugs are easiest to fix with the app's log (*Settings → Export Logs*) and a screenshot.
- **Keep translation quality first.** Changes to prompts, batching or checks should come with a before/after on the same chapter.
- **Run the checks** before opening a pull request: `flutter analyze` and `flutter test`. New behaviour comes with tests; tests do not reach the network or platform channels (see the existing ones for how services are stubbed).
- **Strings** go in `lib/l10n/app_en.arb` with their translations in the other five `.arb` files, then `flutter gen-l10n`.
- **One topic per pull request**, with a description of what changed and how you checked it.

[SETUP.md](SETUP.md) covers building the app.
