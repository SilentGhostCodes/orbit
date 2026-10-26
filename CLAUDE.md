# Orbit — notes for Claude

Orbit is a personal Android reskin of Hiddify. The Orbit UI lives in `lib/orbit/`; everything else
is Hiddify's code, changed as little as possible so upstream fixes can be merged.

- Orbit strings are Russian and written directly in the widgets (no slang keys).
- Generated files (`*.g.dart`, `*.freezed.dart`, translations) are git-ignored:
  `dart run slang && dart run build_runner build -d` after a fresh clone.
- `flutter test test/orbit --update-goldens` renders every screen to `test/orbit/goldens/` with fake
  providers — use it to check UI changes against the design.
