/// Which app Orbit introduces itself as to a subscription panel. Plain subscription links are asked
/// for strictly as Orbit. A subscription from a Happ or INCY link is asked for as that app first, and
/// only if the panel answers it without servers, as the others in [retryOrder]. The app that worked
/// is kept on the subscription, so refreshes go straight to it.
enum PanelClient {
  /// Orbit itself; the user's own panels list "orbit" in their XRAY_JSON rule.
  orbit,

  /// INCY: Remnawave panels answer it with Xray JSON.
  incy,

  /// Happ: the client Remnawave's device headers are modelled on; most panels know it.
  happ,

  /// v2rayNG: nearly every panel knows it and answers with share links.
  v2rayng;

  /// The order a Happ or INCY link's subscription is tried in after its own app.
  static const retryOrder = [orbit, v2rayng, incy, happ];

  static PanelClient fromName(Object? name) => values.firstWhere((c) => c.name == name, orElse: () => orbit);

  /// The headers that identify this app; [orbitAgent] is Orbit's own User-Agent.
  Map<String, String> headers(String orbitAgent) => switch (this) {
    orbit => {'User-Agent': orbitAgent},
    incy => const {
      'User-Agent': 'INCY/3.3.9/android Dalvik/2.1.0',
      'X-Client': 'INCY',
      'X-App-Version': '3.3.9',
      'X-Device-Locale': 'ru_RU',
    },
    // as Happ for Android sends it; the device headers (x-hwid, x-device-os, x-ver-os,
    // x-device-model) come from DeviceInfo, the same for every app
    happ => const {'User-Agent': 'Happ/3.24.1', 'X-Device-Locale': 'ru'},
    v2rayng => const {'User-Agent': 'v2rayNG/1.10.16'},
  };
}
