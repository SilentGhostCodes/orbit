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
- `happ://crypt…` links open (`HappLink`, crypt–crypt5), ported from LeeeeT/happ-decryptor; the keys
  are in `assets/happ/keys.json` (hex n/d/p/q, rebuilt by `tool/happ_keys.py` when crypt5 gets new
  markers). The decrypted URL is still shown in the app for now; the user plans to hide it before
  release.
- Wrapped links go through `WrappedLink`: `unwrap` opens happ://crypt…, incy://crypt1/ and
  happ://add/<url>; `findIn` digs one out of a provider's redirect page (`https://…/t/<token>`
  that opens Happ from a script, button or meta refresh). `SubscriptionRepo.fetch` follows HTTP
  redirects by hand (a Location may be happ://…) and such pages, at most 3 levels deep, and returns
  the final `url`, which is what gets stored.
- Panels pick the format by User-Agent, and some answer an app they do not know without servers
  (Remnawave's `{"isFound":…}` page data, a 404, an HTML page): `SubscriptionRepo.fetch` then asks
  again as INCY, then v2rayNG (`PanelClient`, same HWID headers), and keeps the one that worked on
  the subscription (`Subscription.client`), so refreshes go straight to it. Subscriptions from
  incy:// links start with INCY. Network errors are not retried as other apps.
- Настройки → «Форматы подписок» (`FormatsPage`) lists what can be added; keep it and About's
  «Подписки» row in step when a format is added.

## Planned
- Apply the user's design edits once they send them (from design/Orbit_дизайн.pdf).
- Own encrypted links (orbit://crypt…, our key pair): postponed by the user; only if they bring it up.
- A permanent signing key, before the app goes to other users (the user postponed it).
