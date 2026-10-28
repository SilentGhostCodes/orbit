import 'dart:convert';

import 'package:flutter/services.dart';

/// What the VPN service reports. It runs in its own process (":vpn"), so this is all the app
/// learns about it: a state, when it got there, and an error if it stopped on one.
class VpnStatus {
  const VpnStatus(this.state, {this.since, this.error, this.server});

  final VpnState state;
  final DateTime? since;
  final String? error;

  /// The server the tunnel was started with.
  final String? server;

  static const disconnected = VpnStatus(VpnState.disconnected);

  factory VpnStatus.fromMap(Map<dynamic, dynamic> map) {
    final since = map['since'] as int?;
    return VpnStatus(
      VpnState.values.asNameMap()[map['state']] ?? VpnState.disconnected,
      since: since == null || since == 0 ? null : DateTime.fromMillisecondsSinceEpoch(since),
      error: (map['error'] as String?)?.isEmpty ?? true ? null : map['error'] as String,
      server: (map['server'] as String?)?.isEmpty ?? true ? null : map['server'] as String,
    );
  }
}

enum VpnState { disconnected, connecting, connected, disconnecting }

class InstalledApp {
  const InstalledApp({required this.package, required this.name, required this.system, this.icon});

  final String package;
  final String name;
  final bool system;
  final Uint8List? icon;
}

/// The Kotlin side: VPN service control, libXray, installed apps.
abstract class Native {
  static const _channel = MethodChannel('orbit/native');
  static const _status = EventChannel('orbit/status');

  /// Asks Android for VPN permission if the app does not have it yet. False when the user declined.
  static Future<bool> prepareVpn() async => await _channel.invokeMethod<bool>('prepareVpn') ?? false;

  /// Starts (or restarts with a new config) the tunnel.
  /// [fallback] is run instead if [xrayConfig] fails to start (the subscription's routing).
  static Future<void> start({required String xrayConfig, required Map<String, dynamic> vpn, String? fallback}) =>
      _channel.invokeMethod('start', {'config': xrayConfig, 'vpn': jsonEncode(vpn), 'fallback': fallback});

  static Future<void> stop() => _channel.invokeMethod('stop');

  /// Whether the tunnel comes up after a reboot; read by the boot receiver.
  static Future<void> setAutoConnect(bool on) => _channel.invokeMethod('setAutoConnect', {'on': on});

  static Future<VpnStatus> status() async =>
      VpnStatus.fromMap(await _channel.invokeMethod<Map<dynamic, dynamic>>('status') ?? const {});

  static Stream<VpnStatus> get statusStream =>
      _status.receiveBroadcastStream().map((e) => VpnStatus.fromMap(e as Map<dynamic, dynamic>));

  /// One libXray call (its JSON envelope in and out), run off the main thread. [dns] is the plain
  /// DNS server Xray resolves server names with in this process: Go on Android has none of its own.
  static Future<String> libxray(String request, {required String dns}) async =>
      await _channel.invokeMethod<String>('libxray', {'request': request, 'dns': dns}) ?? '';

  /// Orbit's own ping in libXray (core/libxray): pingBatch with a request method and mode.
  static Future<String> orbitPing(String request, {required String dns}) async =>
      await _channel.invokeMethod<String>('orbitPing', {'request': request, 'dns': dns}) ?? '';

  /// One ICMP echo to [host] through the system's ping, in milliseconds; null if none came back.
  static Future<int?> icmpPing(String host, {required int timeoutSeconds}) async {
    final delay = await _channel.invokeMethod<int>('icmpPing', {'host': host, 'timeout': timeoutSeconds});
    return delay == null || delay < 0 ? null : delay;
  }

  static Future<List<InstalledApp>> installedApps() async {
    final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>('installedApps') ?? const [];
    return [
      for (final m in list)
        InstalledApp(
          package: m['package'] as String,
          name: m['name'] as String,
          system: m['system'] as bool? ?? false,
          icon: m['icon'] as Uint8List?,
        ),
    ];
  }

  static Future<void> openVpnSettings() => _channel.invokeMethod('openVpnSettings');

  static Future<void> requestNotifications() => _channel.invokeMethod('requestNotifications');
}
