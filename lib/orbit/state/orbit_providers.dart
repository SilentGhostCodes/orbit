import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/orbit/utils/server_meta.dart';
import 'package:hiddify/orbit/utils/xray_json.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract class OrbitPrefs {
  /// Connect when the app opens, and when the phone boots (read by the native BootReceiver).
  static final autoConnect = PreferencesNotifier.create<bool, bool>('orbit_auto_connect', true);

  /// What the user set the Kill Switch row to. Android does the blocking itself, in its VPN settings.
  static final killSwitch = PreferencesNotifier.create<bool, bool>('orbit_kill_switch', false);

  /// Hours between subscription refreshes for new subscriptions.
  static final defaultUpdateHours = PreferencesNotifier.create<int, int>('orbit_update_hours', 12);

  /// The server last selected in the core, shown as selected while disconnected.
  static final lastServer = PreferencesNotifier.create<String, String>('orbit_last_server', autoServerTag);

  /// Unix millis of the moment the tunnel came up, so the timer survives the app being closed.
  static final connectedSince = PreferencesNotifier.create<int, int>('orbit_connected_since', 0);
}

/// Stands for the core's auto (best ping) group while the core is not running to name it.
const autoServerTag = '__auto__';

const _platform = MethodChannel('com.hiddify.app/platform');

Future<void> openAndroidVpnSettings() async {
  try {
    await _platform.invokeMethod('open_vpn_settings');
  } catch (_) {}
}

/// When the tunnel came up, or null while it is down. Kept in preferences so a restarted app still
/// counts from the original moment.
final connectedSinceProvider = Provider<DateTime?>((ref) {
  final status = ref.watch(connectionNotifierProvider).valueOrNull;
  final saved = ref.watch(OrbitPrefs.connectedSince);
  if (status is! Connected) {
    if (status is Disconnected && saved != 0) {
      Future.microtask(() => ref.read(OrbitPrefs.connectedSince.notifier).update(0));
    }
    return null;
  }
  if (saved == 0) {
    final now = DateTime.now();
    Future.microtask(() => ref.read(OrbitPrefs.connectedSince.notifier).update(now.millisecondsSinceEpoch));
    return now;
  }
  return DateTime.fromMillisecondsSinceEpoch(saved);
});

/// Connects once when the app starts, if the user wants that and the tunnel is not up already.
final autoConnectOnLaunchProvider = FutureProvider<void>((ref) async {
  if (!ref.read(OrbitPrefs.autoConnect)) return;
  final profile = await ref.read(activeProfileProvider.future);
  if (profile == null) return;
  final status = await ref.read(connectionNotifierProvider.future);
  if (status is Disconnected && status.connectionFailure == null) {
    await ref.read(connectionNotifierProvider.notifier).mayConnect();
  }
});

/// A second-by-second clock for the connection timer.
final tickerProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// A server as the subscription file describes it, readable without the core running.
class OfflineServer {
  const OfflineServer({required this.tag, required this.type, this.transport, this.reality = false});

  final String tag;
  final String type;
  final String? transport;
  final bool reality;

  String get protocol => protocolLabel(type, transport: transport, reality: reality);
}

const _notServers = {'direct', 'block', 'dns', 'selector', 'urltest', 'loadbalance', 'balancer'};

OfflineServer _xrayServer(String tag, Map<String, dynamic> config) {
  final d = describeXrayConfig(config);
  return OfflineServer(tag: tag, type: d.protocol, transport: d.network, reality: d.reality);
}

List<OfflineServer> parseServers(String content) {
  final trimmed = content.trim();
  if (trimmed.startsWith('{')) {
    try {
      final json = jsonDecode(trimmed);
      final outbounds = [
        if (json is Map && json['outbounds'] is List) ...json['outbounds'] as List,
        if (json is Map && json['endpoints'] is List) ...json['endpoints'] as List,
      ];
      return [
        for (final o in outbounds.whereType<Map>())
          if (o['tag'] is String && o['type'] == 'xray' && o['xconfig'] is Map<String, dynamic>)
            _xrayServer(o['tag'] as String, o['xconfig'] as Map<String, dynamic>)
          else if (o['tag'] is String && !_notServers.contains(o['type']))
            OfflineServer(
              tag: o['tag'] as String,
              type: (o['type'] ?? '').toString(),
              transport: (o['transport'] is Map) ? (o['transport'] as Map)['type']?.toString() : null,
              reality:
                  o['tls'] is Map &&
                  (o['tls'] as Map)['reality'] is Map &&
                  ((o['tls'] as Map)['reality'] as Map)['enabled'] == true,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
  var text = trimmed;
  if (!text.contains('://')) {
    final decoded = safeDecodeBase64(text);
    if (decoded.contains('://')) text = decoded;
  }
  final servers = <OfflineServer>[];
  for (final line in const LineSplitter().convert(text)) {
    final uri = Uri.tryParse(line.trim());
    if (uri == null || !uri.hasScheme || uri.scheme == 'http' || uri.scheme == 'https') continue;
    final name = Uri.decodeComponent(uri.fragment);
    final query = uri.queryParameters;
    servers.add(
      OfflineServer(
        tag: name.isEmpty ? uri.host : name,
        type: uri.scheme,
        transport: query['type'],
        reality: query['security'] == 'reality',
      ),
    );
  }
  return servers;
}

/// The servers in a subscription, read from its saved file.
final profileServersProvider = FutureProvider.family<List<OfflineServer>, String>((ref, profileId) async {
  // read again whenever the profile list changes, e.g. after an update
  ref.watch(profilesNotifierProvider);
  final file = ref.watch(profilePathResolverProvider).file(profileId);
  if (!await file.exists()) return const [];
  return parseServers(await file.readAsString());
});

/// One row of the server list, from the core while connected, otherwise from the subscription file.
class ServerRow {
  const ServerRow({
    required this.tag,
    required this.name,
    required this.protocol,
    this.country,
    this.delay,
    this.selected = false,
    this.isAuto = false,
  });

  final String tag;
  final String name;
  final String protocol;
  final String? country;
  final int? delay;
  final bool selected;
  final bool isAuto;
}

class ServerList {
  const ServerList({required this.rows, required this.live, this.groupTag});

  final List<ServerRow> rows;

  /// Whether the rows come from the running core, with pings and a real selection.
  final bool live;
  final String? groupTag;

  ServerRow? get selected => rows.where((r) => r.selected).firstOrNull;
}

/// The server picked while disconnected, chosen in the core once the tunnel is up.
class PendingServer extends Notifier<String?> {
  @override
  String? build() => null;

  // ignore: use_setters_to_change_properties
  void set(String? tag) => state = tag;
}

final pendingServerProvider = NotifierProvider<PendingServer, String?>(PendingServer.new);

bool _isAutoGroup(OutboundInfo o) => o.isGroup || o.type.toLowerCase() == 'urltest';

final serverListProvider = Provider.family<AsyncValue<ServerList>, ProfileEntity>((ref, profile) {
  final offline = ref.watch(profileServersProvider(profile.id));
  final protocols = {for (final s in offline.valueOrNull ?? const <OfflineServer>[]) s.tag: s.protocol};
  final running = ref.watch(serviceRunningProvider);

  if (running && profile.active) {
    final live = ref.watch(proxiesOverviewNotifierProvider);
    if (live case AsyncData(value: final group?)) {
      final rows = [
        for (final o in group.items)
          if (o.isVisible || _isAutoGroup(o))
            ServerRow(
              tag: o.tag,
              name: _isAutoGroup(o) ? 'Авто' : displayName(o.tagDisplay.isNotEmpty ? o.tagDisplay : o.tag),
              protocol: _isAutoGroup(o)
                  ? 'Лучший по пингу'
                  : protocols[o.tag] ?? protocols[o.tagDisplay] ?? protocolLabel(o.type),
              country: _isAutoGroup(o) ? null : guessCountry(o.tag, ipCountry: o.ipinfo.countryCode),
              delay: o.urlTestDelay,
              selected: group.selected == o.tag,
              isAuto: _isAutoGroup(o),
            ),
      ];
      // the auto group first, as in the design
      rows.sort((a, b) => (b.isAuto ? 1 : 0) - (a.isAuto ? 1 : 0));
      return AsyncData(ServerList(rows: rows, live: true, groupTag: group.tag));
    }
    if (live is AsyncLoading) return const AsyncLoading();
  }

  final chosen = ref.watch(pendingServerProvider) ?? ref.watch(OrbitPrefs.lastServer);
  return offline.whenData((servers) {
    final known = servers.any((s) => s.tag == chosen);
    final rows = [
      ServerRow(tag: autoServerTag, name: 'Авто', protocol: 'Лучший по пингу', isAuto: true, selected: !known),
      for (final s in servers)
        ServerRow(
          tag: s.tag,
          name: displayName(s.tag),
          protocol: s.protocol,
          country: guessCountry(s.tag),
          selected: chosen == s.tag,
        ),
    ];
    return ServerList(rows: rows, live: false);
  });
});

/// Applies the server picked while disconnected as soon as the core lists its servers.
final pendingServerApplier = Provider<void>((ref) {
  ref.listen(proxiesOverviewNotifierProvider, (_, next) {
    final group = next.valueOrNull;
    if (group == null) return;
    final pending = ref.read(pendingServerProvider);
    if (pending == null) {
      final current = group.items.where((o) => o.tag == group.selected).firstOrNull;
      if (current != null) {
        final tag = _isAutoGroup(current) ? autoServerTag : current.tag;
        if (ref.read(OrbitPrefs.lastServer) != tag) ref.read(OrbitPrefs.lastServer.notifier).update(tag);
      }
      return;
    }
    final match = pending == autoServerTag
        ? group.items.where(_isAutoGroup).firstOrNull
        : group.items.where((o) => o.tag == pending || o.tagDisplay == pending).firstOrNull ??
              group.items.where((o) => displayName(o.tag) == displayName(pending)).firstOrNull;
    ref.read(pendingServerProvider.notifier).set(null);
    if (match != null && group.selected != match.tag) {
      unawaited(ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, match.tag));
    }
  });
});
