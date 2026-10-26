# Orbit

A minimal Android VPN client for personal use, built on top of
[Hiddify](https://github.com/hiddify/hiddify-app) (sing-box core, Flutter).

Orbit keeps all of Hiddify's engine (subscriptions, VLESS / Reality / XHTTP, Hysteria2, Trojan,
TUN, routing, per-app proxy) and replaces the interface with the Orbit design: three tabs, a
flower-shaped connect button and a mint `#3DD6A0` accent.

## What changed from Hiddify

- New UI in `lib/orbit/`: home, servers, settings, apps through VPN, subscription sheets, theme
  (Manrope + JetBrains Mono, dark only).
- Router (`lib/core/router/go_router/routing_config_notifier.dart`) points at the Orbit screens;
  Hiddify's full settings stay reachable under Settings → Дополнительно.
- No intro screen; Russian locale and "bypass RU" routing by default.
- Auto-connect on app start and on boot (`orbit_auto_connect`, read by `BootReceiver`).
- Kill Switch row opens Android's VPN settings (Always-on + block connections without VPN).
- Android: app id `app.orbit.client`, name and icons "Orbit"; Hiddify's CI replaced by
  `.github/workflows/android.yml`.

## Building

GitHub Actions builds the APKs on every push to `main` (artifact **Orbit-android**) and attaches
them to a release for tags `v*`.

To keep updates installable over each other, add a signing key as repository secrets:

```bash
keytool -genkey -v -keystore orbit.jks -keyalg RSA -keysize 2048 -validity 10000 -alias orbit
base64 -w0 orbit.jks   # → ANDROID_SIGNING_KEY
```

and set `ANDROID_SIGNING_STORE_PASSWORD`, `ANDROID_SIGNING_KEY_PASSWORD`,
`ANDROID_SIGNING_KEY_ALIAS` (`orbit`). Without them every build is signed with a throwaway debug key.

Locally (Flutter 3.38, JDK 17, Android SDK):

```bash
make android-prepare          # deps, codegen, downloads the core into android/app/libs
flutter build apk --split-per-abi --target lib/main_prod.dart
```

Screen previews: `flutter test test/orbit --update-goldens` → `test/orbit/goldens/`.

## License

Hiddify is licensed under the [Hiddify Extended GPLv3](LICENSE.md); Orbit is a personal,
non-commercial modification of it and keeps that license.
