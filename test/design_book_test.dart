// Renders every screen into design/screens/ for the design book (not run in CI).
// FLUTTER_ROOT=/opt/flutter flutter test --update-goldens test/design_book_test.dart
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
import 'package:orbit/ui/about_page.dart';
import 'package:orbit/ui/appearance_page.dart';
import 'package:orbit/ui/apps_page.dart';
import 'package:orbit/ui/logs_page.dart';
import 'package:orbit/ui/ping_settings_page.dart';
import 'package:orbit/ui/settings_page.dart';
import 'package:orbit/ui/shell.dart';
import 'package:orbit/ui/subscription_sheets.dart';

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

final _servers = [
  _server('🇳🇱 Амстердам', 'raw', security: 'reality'),
  _server('🇫🇮 Хельсинки', 'raw', security: 'reality'),
  _server('🇩🇪 Франкфурт CDN', 'xhttp'),
  _server('🇸🇪 Стокгольм', 'ws'),
  _server('🇺🇸 Нью-Йорк', 'raw', security: 'reality'),
  _server('🇹🇷 Стамбул', 'grpc'),
];

final _main = Subscription(
  id: 's1',
  name: 'Основная',
  url: 'https://sub.example.com/a',
  updatedAt: DateTime.now(),
  upload: 8 << 30,
  download: 40 << 30,
  total: 100 << 30,
  expire: DateTime.now().add(const Duration(days: 28, hours: 23)),
  servers: _servers,
);

final _unlimited = Subscription(
  id: 's2',
  name: 'Ghost VPN',
  url: 'https://sub.example.com/b',
  updatedAt: DateTime.now(),
  download: 37 << 30,
  servers: _servers.take(4).toList(),
);

const _dir = 'design/screens';

/// One screen: [build] gets the app; [then] may open a sheet or scroll before the shot.
Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget page, {
  int tab = 0,
  VpnStatus? status,
  List<Subscription>? subs,
  String active = 's1',
  OrbitSettings? settings,
  Future<void> Function(WidgetTester t)? then,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final boot = Boot(
    version: '1.3.0',
    build: '16',
    settings: (settings ?? const OrbitSettings()).copyWith(
      activeSubscription: active,
      selectedServers: const {'s1': '🇳🇱 Амстердам'},
    ),
    subscriptions: subs ?? [_main, _unlimited],
    ruCidrs: const [],
    logPath: '/tmp/orbit-design/xray.log',
  );
  final pings = Pings(
    delays: {
      for (final (i, s) in _servers.indexed) Pings.key('s1', s.name): [38, 29, 44, 52, 118, null][i],
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootProvider.overrideWithValue(boot),
        vpnStatusProvider.overrideWithValue(AsyncData(status ?? VpnStatus.disconnected)),
        pingsProvider.overrideWith(() => _FixedPings(pings)),
        tabProvider.overrideWith(() => _FixedTab(tab)),
      ],
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: orbitTheme(), home: page),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  if (then != null) {
    await then(tester);
    await tester.pump(const Duration(seconds: 1));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../$_dir/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

class _FixedPings extends PingsNotifier {
  _FixedPings(this.initial);

  final Pings initial;

  @override
  Pings build() => initial;
}

class _FixedTab extends TabNotifier {
  _FixedTab(this.initial);

  final int initial;

  @override
  int build() => initial;
}

Future<void> Function(WidgetTester) _open(Future<void> Function(BuildContext) show) => (t) async {
  show(t.element(find.byType(Scaffold).first));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
};

void main() {
  setUpAll(() async {
    await _font('Manrope', [for (final w in [400, 500, 600, 700]) 'assets/fonts/Manrope-$w.ttf']);
    await _font('JetBrainsMono', ['assets/fonts/JetBrainsMono-400.ttf', 'assets/fonts/JetBrainsMono-500.ttf']);
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      await _font('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    }
    Directory('/tmp/orbit-design').createSync(recursive: true);
    File('/tmp/orbit-design/service.log').writeAsStringSync(
      '12:04:11 Подключение: 🇳🇱 Амстердам\n12:04:12 Xray запущен\n12:04:12 Туннель поднят\n',
    );
    File('/tmp/orbit-design/xray.log').writeAsStringSync(
      '2026/10/28 12:04:12 [Warning] core: Xray 26.10.21 started\n'
      '2026/10/28 12:04:13 [Info] proxy/vless/outbound: tunneling request to tcp:www.google.com:443\n',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('orbit/native'),
      (call) async => switch (call.method) {
        'status' => {'state': 'disconnected'},
        'libxray' => '{"success":true,"data":{"version":"26.10.21"}}',
        'installedApps' => [
          for (final (p, n) in [
            ('org.telegram.messenger', 'Telegram'),
            ('com.google.android.youtube', 'YouTube'),
            ('com.instagram.android', 'Instagram'),
            ('ru.sberbankmobile', 'СберБанк'),
            ('com.whatsapp', 'WhatsApp'),
            ('com.discord', 'Discord'),
            ('ru.yandex.taxi', 'Яндекс Go'),
            ('com.spotify.music', 'Spotify'),
          ])
            {'package': p, 'name': n, 'system': false},
        ],
        _ => null,
      },
    );
  });

  final on = VpnStatus(
    VpnState.connected,
    since: DateTime.now().subtract(const Duration(hours: 1, minutes: 24, seconds: 37)),
    server: '🇳🇱 Амстердам',
  );

  testWidgets('01', (t) => _shoot(t, '01_first_run', const Shell(), subs: const [], active: ''));
  testWidgets('02', (t) => _shoot(t, '02_home_off', const Shell()));
  testWidgets('03', (t) => _shoot(t, '03_home_connecting', const Shell(), status: const VpnStatus(VpnState.connecting)));
  testWidgets('04', (t) => _shoot(t, '04_home_on', const Shell(), status: on));
  testWidgets('05', (t) => _shoot(t, '05_home_unlimited', const Shell(), active: 's2'));
  testWidgets('06', (t) => _shoot(t, '06_subscriptions', const Shell(), then: _open(showSubscriptionsSheet)));
  testWidgets('07', (t) => _shoot(t, '07_add_subscription', const Shell(), then: _open(showAddSubscriptionSheet)));
  testWidgets('08', (t) => _shoot(t, '08_servers', const Shell(), tab: 1, status: on));
  testWidgets('09', (t) => _shoot(t, '09_settings', const Shell(), tab: 2));
  testWidgets(
    '10',
    (t) => _shoot(
      t,
      '10_routing_picker',
      const Shell(),
      tab: 2,
      then: _open(
        (c) => pick<RoutingMode>(
          c,
          title: 'Маршрутизация',
          current: RoutingMode.bypassRu,
          options: const {
            RoutingMode.bypassRu: ('Обход RU', 'Российские сайты и IP напрямую'),
            RoutingMode.all: ('Всё через VPN', 'Без исключений'),
          },
          onSelected: (_) {},
        ),
      ),
    ),
  );
  testWidgets(
    '11',
    (t) => _shoot(
      t,
      '11_apps',
      const AppsPage(),
      settings: const OrbitSettings(appsMode: AppsMode.exclude, apps: {'ru.sberbankmobile', 'ru.yandex.taxi'}),
    ),
  );
  testWidgets('12', (t) => _shoot(t, '12_ping', const PingSettingsPage()));
  testWidgets(
    '13',
    (t) => _shoot(
      t,
      '13_ping_bottom',
      const PingSettingsPage(),
      then: (t) async {
        await t.drag(find.byType(ListView), const Offset(0, -2000));
        await t.pump();
      },
    ),
  );
  testWidgets('14', (t) => _shoot(t, '14_appearance', const AppearancePage()));
  testWidgets(
    '15',
    (t) => _shoot(
      t,
      '15_logs',
      const LogsPage(),
      settings: const OrbitSettings(debugLog: true),
      // the page reads the log files for real
      then: (t) => t.runAsync(() async {
        await t.tap(find.byTooltip('Обновить'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }),
    ),
  );
  testWidgets('16', (t) => _shoot(t, '16_about', const AboutPage()));
}
