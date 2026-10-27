# Orbit — notes for Claude

Orbit is written from scratch (not a fork). Flutter UI in `lib/`, the tunnel in Kotlin
(`android/app/src/main/kotlin/app/orbit/client/`), the core is libXray built in CI.

- UI strings are Russian, written directly in the widgets.
- The VPN service runs in the `:vpn` process; the app talks to it through files in `filesDir`
  (`active.json`, `vpn.json`, `vpn_state.json`) and the `app.orbit.client.STATUS` broadcast.
- libXray: one process may run only one Xray instance, and pingBatch refuses while it runs one.
- There is no Android SDK in the cloud container; Kotlin is only compiled in CI. CI failures are
  readable through the check-run annotations API (the build log itself is not downloadable here).
- `flutter test --update-goldens test/preview_test.dart` renders the screens for a visual check.
- Versions: raise `version:` in pubspec.yaml with every change the user will see (minor for features,
  patch for fixes; the `+N` part is replaced by CI's run number). About shows version and build.
