import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/xray_config.dart';
import 'package:orbit/data/device.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/data/subscription_repo.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/shell.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: OrbitColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final results = await Future.wait([
    PackageInfo.fromPlatform(),
    OrbitSettings.load(),
    SubscriptionRepo.load(),
    getApplicationSupportDirectory(),
    rootBundle.loadString('assets/geo/ru4.txt'),
    rootBundle.loadString('assets/geo/ru6.txt'),
    rootBundle.loadString('assets/xray/geosite.txt'),
    rootBundle.loadString('assets/xray/geoip.txt'),
    DeviceInfo.load(),
  ]);
  final boot = Boot(
    version: (results[0] as PackageInfo).version,
    build: (results[0] as PackageInfo).buildNumber,
    settings: results[1] as OrbitSettings,
    subscriptions: results[2] as List<Subscription>,
    logPath: '${(results[3] as Directory).path}/xray.log',
    ruCidrs: [...parseCidrList(results[4] as String), ...parseCidrList(results[5] as String)],
    geo: GeoCodes.parse(results[6] as String, results[7] as String),
    device: results[8] as DeviceInfo,
  );

  runApp(ProviderScope(overrides: [bootProvider.overrideWithValue(boot)], child: const OrbitApp()));
}

class OrbitApp extends ConsumerStatefulWidget {
  const OrbitApp({super.key});

  @override
  ConsumerState<OrbitApp> createState() => _OrbitAppState();
}

class _OrbitAppState extends ConsumerState<OrbitApp> {
  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accent)));
    if (accent != OrbitColors.accent) {
      OrbitColors.accent = accent;
      // widgets read the accent directly rather than through the theme: rebuild them all
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void rebuild(Element e) {
          e.markNeedsBuild();
          e.visitChildren(rebuild);
        }

        if (mounted) (context as Element).visitChildren(rebuild);
      });
    }
    final theme = orbitTheme();
    return MaterialApp(
      title: 'Orbit',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const Shell(),
    );
  }
}
