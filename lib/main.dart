import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/xray_config.dart';
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
  ]);
  final boot = Boot(
    version: (results[0] as PackageInfo).version,
    build: (results[0] as PackageInfo).buildNumber,
    settings: results[1] as OrbitSettings,
    subscriptions: results[2] as List<Subscription>,
    logPath: '${(results[3] as Directory).path}/xray.log',
    ruCidrs: [...parseCidrList(results[4] as String), ...parseCidrList(results[5] as String)],
  );

  runApp(ProviderScope(overrides: [bootProvider.overrideWithValue(boot)], child: const OrbitApp()));
}

class OrbitApp extends StatelessWidget {
  const OrbitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Orbit',
    debugShowCheckedModeBanner: false,
    theme: orbitTheme(),
    darkTheme: orbitTheme(),
    themeMode: ThemeMode.dark,
    home: const Shell(),
  );
}
