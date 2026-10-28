import 'dart:math';

import 'package:orbit/core/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Orbit tells a panel about the phone, for Remnawave's device limit (HWID).
class DeviceInfo {
  const DeviceInfo({required this.hwid, this.osVersion = '', this.model = ''});

  /// A random id made on first launch and kept until the app is removed.
  final String hwid;
  final String osVersion;
  final String model;

  /// The headers Remnawave reads: x-hwid, x-device-os, x-ver-os, x-device-model.
  Map<String, String> get headers => {
    'x-hwid': hwid,
    'x-device-os': 'Android',
    if (osVersion.isNotEmpty) 'x-ver-os': osVersion,
    if (model.isNotEmpty) 'x-device-model': model,
  };

  static const _key = 'orbit_hwid';

  static Future<DeviceInfo> load() async {
    final prefs = await SharedPreferences.getInstance();
    var hwid = prefs.getString(_key);
    if (hwid == null || hwid.isEmpty) {
      final random = Random.secure();
      hwid = [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
      await prefs.setString(_key, hwid);
    }
    final info = await Native.deviceInfo().catchError((_) => const <String, String>{});
    return DeviceInfo(hwid: hwid, osVersion: info['osVersion'] ?? '', model: info['model'] ?? '');
  }
}
