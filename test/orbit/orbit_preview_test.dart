// Renders the Orbit screens with stand-in data, to compare them against the design.
// Run with: flutter test test/orbit --update-goldens   (PNGs land in test/orbit/goldens)
@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/orbit/home/orbit_home_page.dart';
import 'package:hiddify/orbit/servers/orbit_servers_page.dart';
import 'package:hiddify/orbit/settings/orbit_settings_page.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/subscriptions/subscription_sheets.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(File(path).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

final _profile = ProfileEntity.remote(
  id: 'p1',
  active: true,
  name: 'Основная',
  url: 'https://sub.example.com/api/sub/a8f3',
  lastUpdate: DateTime(2026),
  subInfo: SubscriptionInfo(
    upload: 8 * 1024 * 1024 * 1024,
    download: 40 * 1024 * 1024 * 1024,
    total: 100 * 1024 * 1024 * 1024,
    expire: DateTime.now().add(const Duration(days: 28, hours: 23)),
  ),
);

class _FakeActiveProfile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(_profile);
}

class _FakeProfiles extends ProfilesNotifier {
  @override
  Stream<List<ProfileEntity>> build() => Stream.value([
    _profile,
    ProfileEntity.remote(
      id: 'p2',
      active: false,
      name: 'Резерв',
      url: 'https://b',
      lastUpdate: DateTime(2026),
      subInfo: SubscriptionInfo(
        upload: 0,
        download: 6 * 1024 * 1024 * 1024,
        total: 50 * 1024 * 1024 * 1024,
        expire: DateTime.now().add(const Duration(days: 67, hours: 23)),
      ),
    ),
    ProfileEntity.remote(
      id: 'p3',
      active: false,
      name: 'Рабочая',
      url: 'https://c',
      lastUpdate: DateTime(2026),
      subInfo: SubscriptionInfo(
        upload: 0,
        download: 1,
        total: 0,
        expire: DateTime.now().add(const Duration(days: 2, hours: 23)),
      ),
    ),
  ]);
}

class _FakeConnection extends ConnectionNotifier {
  _FakeConnection(this.status);
  final ConnectionStatus status;
  @override
  Stream<ConnectionStatus> build() => Stream.value(status);
}

class _FakeActiveProxy extends ActiveProxyNotifier {
  @override
  Stream<OutboundInfo> build() => Stream.value(OutboundInfo(tag: '🇳🇱 Амстердам', urlTestDelay: 38));
}

final _servers = ServerList(
  live: true,
  groupTag: 'select',
  rows: const [
    ServerRow(tag: 'auto', name: 'Авто', protocol: 'Лучший по пингу', isAuto: true),
    ServerRow(tag: 'nl', name: 'Амстердам', protocol: 'VLESS Reality', country: 'NL', delay: 38, selected: true),
    ServerRow(tag: 'fi', name: 'Хельсинки', protocol: 'VLESS Reality', country: 'FI', delay: 29),
    ServerRow(tag: 'de', name: 'Франкфурт', protocol: 'VLESS XHTTP', country: 'DE', delay: 44),
    ServerRow(tag: 'se', name: 'Стокгольм', protocol: 'Hysteria2', country: 'SE', delay: 52),
    ServerRow(tag: 'us', name: 'Нью-Йорк', protocol: 'VLESS Reality', country: 'US', delay: 118),
    ServerRow(tag: 'tr', name: 'Стамбул', protocol: 'Trojan', country: 'TR', delay: 65535),
  ],
);

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget page, {
  ConnectionStatus status = const Disconnected(),
  bool hasProfiles = true,
  Future<void> Function(BuildContext)? open,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      activeProfileProvider.overrideWith(_FakeActiveProfile.new),
      profilesNotifierProvider.overrideWith(_FakeProfiles.new),
      hasAnyProfileProvider.overrideWith((ref) => Stream.value(hasProfiles)),
      connectionNotifierProvider.overrideWith(() => _FakeConnection(status)),
      serviceRunningProvider.overrideWithValue(status is Connected),
      activeProxyNotifierProvider.overrideWith(_FakeActiveProxy.new),
      serverListProvider.overrideWith((ref, _) => AsyncData(_servers)),
      profileServersProvider.overrideWith(
        (ref, _) async => List.generate(6, (i) => OfflineServer(tag: '$i', type: 'vless')),
      ),
      connectedSinceProvider.overrideWithValue(
        DateTime.now().subtract(const Duration(hours: 1, minutes: 24, seconds: 37)),
      ),
      tickerProvider.overrideWith((ref) => Stream.value(DateTime.now())),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));

  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: orbitTheme(), home: page),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(seconds: 1));
  if (open != null) {
    unawaited(open(tester.element(find.byType(Scaffold).first)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  // let the providers' dispose delays and the flower's spin run out
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void unawaited(Future<void> _) {}

void main() {
  setUpAll(() async {
    await _loadFont('Manrope', [for (final w in [400, 500, 600, 700]) 'assets/fonts/Manrope-$w.ttf']);
    await _loadFont('JetBrainsMono', ['assets/fonts/JetBrainsMono-400.ttf', 'assets/fonts/JetBrainsMono-500.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('01 first run', (t) => _shoot(t, '01_first_run', const OrbitHomePage(), hasProfiles: false));
  testWidgets('02 home off', (t) => _shoot(t, '02_home_off', const OrbitHomePage()));
  testWidgets('03 home on', (t) => _shoot(t, '03_home_on', const OrbitHomePage(), status: const Connected()));
  testWidgets(
    '04 subscriptions',
    (t) => _shoot(t, '04_subscriptions', const OrbitHomePage(), open: showSubscriptionsSheet),
  );
  testWidgets(
    '05 add subscription',
    (t) => _shoot(t, '05_add', const OrbitHomePage(), open: (c) => showAddSubscriptionSheet(c, 'https://sub.example.com/api/sub/a8f3')),
  );
  testWidgets('06 servers', (t) => _shoot(t, '06_servers', const OrbitServersPage(), status: const Connected()));
  testWidgets('07 settings', (t) => _shoot(t, '07_settings', const OrbitSettingsPage()));
}
