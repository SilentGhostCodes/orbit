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

- Subscription routing (on by default): a server's `routing`/`dns` from Xray JSON replace Orbit's
  routing; rules naming geo lists the APK lacks are dropped (`GeoCodes`), and the service falls back to
  `fallback.json` (Orbit's routing) if Xray refuses the panel's config. Geo lists: runetfreedom,
  trimmed in CI by `core/geotrim` per `core/geo/*.rules` into `assets/xray/` (the .dat files are not
  committed; the code manifests are).

- The accent colour is user-picked: `OrbitColors.accent` is mutable, set by `OrbitApp` from settings,
  which then rebuilds every element. Never use it in a `const` expression.
- Subscription requests carry Remnawave's HWID headers (`DeviceInfo`): a random id kept in prefs, so it
  changes when the app is removed (builds are still signed with throwaway keys).

- `incy://crypt1/` links open (`IncyLink`): INCY publishes the format and key for other clients (MIT).
  Happ's crypt links stay unsupported: their keys were extracted from Happ, not published.

## Planned
- Apply the user's design edits once they send them (from design/Orbit_дизайн.pdf).
- Own encrypted links (orbit://crypt…, our key pair): postponed by the user; only if they bring it up.
- A permanent signing key, before the app goes to other users (the user postponed it).
