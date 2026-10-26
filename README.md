# Orbit

A minimal Android VPN client, written from scratch in Flutter/Dart on top of
[Xray-core](https://github.com/XTLS/Xray-core) (through XTLS's [libXray](https://github.com/XTLS/libXray)).

- **Subscriptions:** Xray JSON (Remnawave, Marzban) as the panel wrote it, share links and base64
  through libXray. Traffic and expiry from `subscription-userinfo`, the name from `profile-title`.
  The User-Agent is `Orbit/<version> (android)`: in Remnawave, add `orbit` to the XRAY_JSON rule.
- **Protocols:** whatever Xray-core runs — VLESS (Reality, XHTTP, WS, gRPC…), VMess, Trojan,
  Shadowsocks, Hysteria2; CDN setups with XHTTP `extra`/`downloadSettings` included.
- **Tunnel:** Android's VPN descriptor goes straight to Xray's own `tun` inbound; one Xray instance
  is the whole VPN. It runs in a separate process (`:vpn`), so pings work while connected.
- **Routing:** «Обход RU» (Russian domains and IP ranges direct, list in `assets/geo/`) or everything
  through the server; per-app include/exclude; DNS over HTTPS through the server; TLS fragmentation.
- Auto-connect on start and boot, a quick settings tile, logs in the app.

## Layout

| Path | What |
| --- | --- |
| `lib/core/` | `native.dart` (channels to Kotlin), `libxray.dart`, `xray_config.dart` (the config the tunnel runs) |
| `lib/data/` | models, subscription parsing and storage, settings |
| `lib/state/` | Riverpod providers: subscriptions, VPN status, pings, connecting |
| `lib/ui/`, `lib/widgets/`, `lib/theme/` | screens and the Orbit look |
| `android/app/src/main/kotlin/app/orbit/client/` | `OrbitVpnService` (tunnel), `MainActivity` (bridge), tile, boot receiver |
| `core/LIBXRAY_COMMIT` | the libXray commit CI builds |

## Building

GitHub Actions builds libXray (cached until `core/` changes) and the APKs on every push to `main`,
and publishes them as a release. To install updates over each other, add a signing key as secrets:

```bash
keytool -genkey -v -keystore orbit.jks -keyalg RSA -keysize 2048 -validity 10000 -alias orbit
base64 -w0 orbit.jks   # → ANDROID_SIGNING_KEY
```

plus `ANDROID_SIGNING_STORE_PASSWORD`, `ANDROID_SIGNING_KEY_PASSWORD`, `ANDROID_SIGNING_KEY_ALIAS`.

Locally: build libXray (`python3 build/main.py android` in a libXray checkout), put `libXray.aar`
in `android/app/libs/`, then `flutter build apk --split-per-abi`.

`flutter test --update-goldens test/preview_test.dart` renders the screens to `test/goldens/`.
