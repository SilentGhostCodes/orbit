// Renders the screens with stand-in data. `flutter test --update-goldens test/preview_test.dart`
// writes them to test/goldens/ for a look; without the flag they are compared.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/appearance_page.dart';
import 'package:orbit/ui/home_page.dart';
import 'package:orbit/ui/servers_page.dart';
import 'package:orbit/ui/settings_page.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(File(p).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

Server _server(String name, String network, {String security = 'tls'}) => Server(
  name: name,
  outbounds: [
    {
      'tag': 'proxy',
      'protocol': 'vless',
      'streamSettings': {'network': network, 'security': security},
    },
  ],
);

final _sub = Subscription(
  id: 's1',
  name: 'Основная',
  url: 'https://sub.example.com/a',
  updatedAt: DateTime(2026),
  upload: 8 << 30,
  download: 40 << 30,
  total: 100 << 30,
  expire: DateTime.now().add(const Duration(days: 28, hours: 23)),
  servers: [
    _server('🇳🇱 Амстердам', 'raw', security: 'reality'),
    _server('🇫🇮 Хельсинки', 'raw', security: 'reality'),
    _server('🇩🇪 Франкфурт CDN', 'xhttp'),
    _server('🇸🇪 Стокгольм', 'ws'),
    _server('🇺🇸 Нью-Йорк', 'raw', security: 'reality'),
    _server('🇹🇷 Стамбул', 'grpc'),
  ],
);

final _unlimited = Subscription(
  id: 's1',
  name: 'Ghost VPN',
  url: 'https://sub.example.com/b',
  updatedAt: DateTime(2026),
  download: 37 << 30,
  servers: _sub.servers,
);

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget page, {
  VpnStatus? status,
  bool empty = false,
  bool unlimited = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final boot = Boot(
    version: '1.0.0',
    settings: OrbitSettings(activeSubscription: 's1', selectedServers: const {'s1': '🇳🇱 Амстердам'}),
    subscriptions: empty ? const [] : [if (unlimited) _unlimited else _sub],
    ruCidrs: const [],
    logPath: '/tmp/xray.log',
  );
  final pings = Pings(
    delays: {
      for (final (i, s) in _sub.servers.indexed) Pings.key('s1', s.name): [38, 29, 44, 52, 118, null][i],
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootProvider.overrideWithValue(boot),
        vpnStatusProvider.overrideWithValue(AsyncData(status ?? VpnStatus.disconnected)),
        pingsProvider.overrideWith(() => _FixedPings(pings)),
      ],
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: orbitTheme(), home: page),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

class _FixedPings extends PingsNotifier {
  _FixedPings(this.initial);

  final Pings initial;

  @override
  Pings build() => initial;
}

void main() {
  setUpAll(() async {
    await _font('Manrope', [for (final w in [400, 500, 600, 700]) 'assets/fonts/Manrope-$w.ttf']);
    await _font('JetBrainsMono', ['assets/fonts/JetBrainsMono-400.ttf', 'assets/fonts/JetBrainsMono-500.ttf']);
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      await _font('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    }
  });

  testWidgets('first run', (t) => _shoot(t, 'first_run', const HomePage(), empty: true));
  testWidgets('home off', (t) => _shoot(t, 'home_off', const HomePage()));
  testWidgets(
    'home on',
    (t) => _shoot(
      t,
      'home_on',
      const HomePage(),
      status: VpnStatus(
        VpnState.connected,
        since: DateTime.now().subtract(const Duration(hours: 1, minutes: 24, seconds: 37)),
        server: '🇳🇱 Амстердам',
      ),
    ),
  );
  testWidgets('servers', (t) => _shoot(t, 'servers', const ServersPage()));
  testWidgets(
    'home connecting',
    (t) => _shoot(t, 'home_connecting', const HomePage(), status: const VpnStatus(VpnState.connecting)),
  );
  testWidgets('home unlimited', (t) => _shoot(t, 'home_unlimited', const HomePage(), unlimited: true));
  testWidgets('settings', (t) => _shoot(t, 'settings', const SettingsPage()));
  testWidgets('appearance', (t) => _shoot(t, 'appearance', const AppearancePage()));
}
