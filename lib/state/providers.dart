import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/direct_ping.dart';
import 'package:orbit/core/libxray.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/core/xray_config.dart';
import 'package:orbit/data/device.dart';
import 'package:orbit/data/happ_link.dart';
import 'package:orbit/data/incy_link.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/data/subscription_repo.dart';

/// What main() reads before the first frame.
class Boot {
  const Boot({
    required this.version,
    this.build = '',
    required this.settings,
    required this.subscriptions,
    required this.ruCidrs,
    required this.logPath,
    this.geo = const GeoCodes(),
    this.device,
  });

  /// From pubspec.yaml's `version`, raised with every release.
  final String version;

  /// The CI build number (the run number), which also makes Android's versionCode.
  final String build;
  final OrbitSettings settings;
  final List<Subscription> subscriptions;
  final List<String> ruCidrs;
  final String logPath;

  /// The geo lists shipped in the APK, for the subscription's routing.
  final GeoCodes geo;

  /// HWID and the phone, sent with subscription requests.
  final DeviceInfo? device;

  String get userAgent => 'Orbit/$version (android)';
}

final bootProvider = Provider<Boot>((ref) => throw UnimplementedError('overridden in main'));

// --- settings ---

final settingsProvider = NotifierProvider<SettingsNotifier, OrbitSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<OrbitSettings> {
  @override
  OrbitSettings build() => ref.read(bootProvider).settings;

  /// [reconnect]: the change shapes the tunnel (routing, DNS, apps…), so a running one restarts.
  Future<void> change(OrbitSettings Function(OrbitSettings s) edit, {bool reconnect = false}) async {
    state = edit(state);
    await state.save();
    if (reconnect) await ref.read(connectionProvider.notifier).reconnectIfConnected();
  }

  Future<void> selectServer(String subscriptionId, String? serverName) => change(
    (s) => s.copyWith(
      selectedServers: {
        for (final e in s.selectedServers.entries)
          if (e.key != subscriptionId) e.key: e.value,
        subscriptionId: ?serverName,
      },
    ),
  );
}

// --- subscriptions ---

final subscriptionsProvider = NotifierProvider<SubscriptionsNotifier, List<Subscription>>(SubscriptionsNotifier.new);

/// Subscription ids being downloaded right now.
final updatingProvider = NotifierProvider<UpdatingNotifier, Set<String>>(UpdatingNotifier.new);

class UpdatingNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(String id, bool on) => state = on ? {...state, id} : ({...state}..remove(id));
}

class SubscriptionsNotifier extends Notifier<List<Subscription>> {
  @override
  List<Subscription> build() => ref.read(bootProvider).subscriptions;

  SubscriptionRepo get _repo => SubscriptionRepo(ref.read(bootProvider).userAgent, device: ref.read(bootProvider).device);

  Future<void> _store(List<Subscription> next) async {
    state = next;
    await SubscriptionRepo.save(next);
    final settings = ref.read(settingsProvider);
    if (settings.activeSubscription == null || !next.any((s) => s.id == settings.activeSubscription)) {
      await ref
          .read(settingsProvider.notifier)
          .change((s) => next.isEmpty ? s.copyWith(clearActive: true) : s.copyWith(activeSubscription: next.first.id));
    }
  }

  /// A subscription link, or share links / Xray JSON pasted as text.
  Future<Subscription> add(String input, {bool autoUpdate = true, int updateHours = 12}) async {
    var text = input.trim();
    String? givenName;
    if (IncyLink.matches(text)) {
      final link = IncyLink.decrypt(text);
      if (link == null) throw SubscriptionException('Не удалось открыть ссылку incy://');
      text = link.url.trim();
      givenName = link.name;
    } else if (HappLink.matches(text)) {
      try {
        text = (await HappLink.decrypt(text)).trim();
      } on HappLinkException catch (e) {
        throw SubscriptionException(e.message);
      }
      // usually a subscription URL; anything else (share links) is parsed as text below
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final Subscription sub;
    if (text.startsWith('http://') || text.startsWith('https://')) {
      final existing = state.where((s) => s.url == text).firstOrNull;
      if (existing != null) {
        await refresh(existing.id);
        return state.firstWhere((s) => s.id == existing.id);
      }
      final r = await _repo.fetch(text);
      sub = Subscription(
        id: id,
        url: text,
        name: r.info.title ?? givenName ?? r.fallbackName,
        servers: r.servers,
        updatedAt: DateTime.now(),
        upload: r.info.upload,
        download: r.info.download,
        total: r.info.total,
        expire: r.info.expire,
        autoUpdate: autoUpdate,
        updateHours: updateHours,
      );
    } else {
      sub = Subscription(
        id: id,
        name: 'Мои серверы',
        servers: await SubscriptionRepo.parseBody(text),
        updatedAt: DateTime.now(),
        autoUpdate: false,
      );
    }
    await _store([...state, sub]);
    // a new subscription becomes the one in use
    await ref.read(settingsProvider.notifier).change((s) => s.copyWith(activeSubscription: sub.id));
    return sub;
  }

  Future<void> refresh(String id) async {
    final sub = state.where((s) => s.id == id).firstOrNull;
    if (sub?.url == null) return;
    String serverJson(Subscription? s, String? name) =>
        jsonEncode(s?.servers.where((x) => x.name == name).firstOrNull?.toJson());
    final running = ref.read(vpnStatusProvider).value?.server;
    final before = serverJson(sub, running);
    final updating = ref.read(updatingProvider.notifier);
    updating.set(id, true);
    try {
      final r = await _repo.fetch(sub!.url!);
      await _store([
        for (final s in state)
          if (s.id == id)
            s.copyWith(
              name: r.info.title ?? s.name,
              servers: r.servers,
              updatedAt: DateTime.now(),
              upload: r.info.upload,
              download: r.info.download,
              total: r.info.total,
              expire: r.info.expire,
              clearExpire: r.info.expire == null,
            )
          else
            s,
      ]);
    } finally {
      updating.set(id, false);
    }
    // the running tunnel uses the old copy of the server; restart it only if that server changed
    final after = serverJson(state.where((s) => s.id == id).firstOrNull, running);
    if (ref.read(settingsProvider).activeSubscription == id && before != after) {
      await ref.read(connectionProvider.notifier).reconnectIfConnected();
    }
  }

  /// [onlyDue]: just the ones whose auto-update interval has passed. Errors are left out quietly.
  Future<void> refreshAll({bool onlyDue = false}) async {
    for (final s in [...state]) {
      if (s.url == null || (onlyDue && !s.needsUpdate)) continue;
      try {
        await refresh(s.id);
      } on Object {
        // shown on the next manual update instead
      }
    }
  }

  Future<void> remove(String id) async {
    final wasActive = ref.read(settingsProvider).activeSubscription == id;
    await _store([...state.where((s) => s.id != id)]);
    if (wasActive && ref.read(vpnStateProvider) != VpnState.disconnected) {
      await ref.read(connectionProvider.notifier).disconnect();
    }
  }

  Future<void> setAutoUpdate(String id, bool on) async =>
      _store([for (final s in state) s.id == id ? s.copyWith(autoUpdate: on) : s]);

  Future<void> setUpdateHours(String id, int hours) async =>
      _store([for (final s in state) s.id == id ? s.copyWith(updateHours: hours) : s]);
}

final activeSubscriptionProvider = Provider<Subscription?>((ref) {
  final subs = ref.watch(subscriptionsProvider);
  final id = ref.watch(settingsProvider.select((s) => s.activeSubscription));
  return subs.where((s) => s.id == id).firstOrNull ?? subs.firstOrNull;
});

// --- VPN status ---

final vpnStatusProvider = StreamProvider<VpnStatus>((ref) async* {
  yield await Native.status();
  yield* Native.statusStream;
});

final vpnStateProvider = Provider<VpnState>(
  (ref) => ref.watch(vpnStatusProvider).value?.state ?? VpnState.disconnected,
);

// --- pings ---

class Pings {
  const Pings({this.delays = const {}, this.running = const {}, this.error});

  /// Milliseconds by [key]; null for a server that did not answer.
  final Map<String, int?> delays;
  final Set<String> running;

  /// Why the last ping failed as a whole (libXray could not run it), for the server list.
  final String? error;

  static String key(String subscriptionId, String server) => '$subscriptionId|$server';

  /// For [PingLabel]: null when not tested yet, -1 when the server did not answer.
  int? shown(String subscriptionId, String server) {
    final k = key(subscriptionId, server);
    return delays.containsKey(k) ? (delays[k] ?? -1) : null;
  }
}

final pingsProvider = NotifierProvider<PingsNotifier, Pings>(PingsNotifier.new);

class PingsNotifier extends Notifier<Pings> {
  @override
  Pings build() => const Pings();

  /// Pings every server of [sub] the way the Пинг settings say, filling the list in as answers
  /// come. Through the proxy that is [LibXray.pingBatchSize] servers per libXray call; TCP and ICMP
  /// go to all servers at once. The app itself is outside the tunnel, so this is the real round trip
  /// to each server, connected or not.
  Future<Map<String, int?>> pingAll(Subscription sub) async {
    final keys = [for (final s in sub.servers) Pings.key(sub.id, s.name)];
    state = Pings(delays: state.delays, running: {...state.running, ...keys});
    final settings = ref.read(settingsProvider);
    final result = <String, int?>{};
    String? error;

    void publish(Map<String, int?> answered) {
      result.addAll(answered);
      state = Pings(
        delays: {...state.delays, for (final e in answered.entries) Pings.key(sub.id, e.key): e.value},
        running: {...state.running}..removeAll([for (final name in answered.keys) Pings.key(sub.id, name)]),
        error: error,
      );
    }

    if (!settings.pingType.viaProxy) {
      final direct = settings.pingType == PingType.tcp ? DirectPing.tcp : DirectPing.icmp;
      await Future.wait([
        for (final s in sub.servers)
          direct(s, timeoutSeconds: settings.pingTimeout).then((delay) => publish({s.name: delay})),
      ]);
      return result;
    }

    LibXray.dns = settings.dnsChoice.ip;
    for (var i = 0; i < sub.servers.length; i += LibXray.pingBatchSize) {
      final batch = sub.servers.skip(i).take(LibXray.pingBatchSize).toList();
      List<int?> delays;
      try {
        delays = await LibXray.ping(
          [for (final s in batch) pingConfig(s, fragment: settings.fragmentOptions)],
          timeoutSeconds: settings.pingTimeout,
          url: settings.pingUrl,
          method: settings.pingType == PingType.proxyHead ? 'HEAD' : 'GET',
          mode: settings.pingMode.id,
        );
      } on Object catch (e) {
        delays = const [];
        error = e.toString();
      }
      publish({for (final (j, s) in batch.indexed) s.name: j < delays.length ? delays[j] : null});
    }
    return result;
  }
}

// --- connecting ---

class ConnectionUi {
  const ConnectionUi({this.picking = false, this.error});

  /// Pinging to pick the fastest server for "Авто".
  final bool picking;
  final String? error;
}

final connectionProvider = NotifierProvider<ConnectionController, ConnectionUi>(ConnectionController.new);

class ConnectionController extends Notifier<ConnectionUi> {
  @override
  ConnectionUi build() => const ConnectionUi();

  bool get _up => ref.read(vpnStateProvider) != VpnState.disconnected;

  Future<void> toggle() async => _up ? disconnect() : connect();

  Future<void> disconnect() async {
    state = const ConnectionUi();
    await Native.stop();
  }

  Future<void> reconnectIfConnected() async {
    if (ref.read(vpnStateProvider) == VpnState.connected) await connect();
  }

  /// The server to use: the picked one, or under "Авто" the fastest by a fresh ping.
  Future<Server?> _pick(Subscription sub) async {
    final picked = ref.read(settingsProvider).selectedServers[sub.id];
    final server = sub.servers.where((s) => s.name == picked).firstOrNull;
    if (server != null) return server;
    if (sub.servers.length == 1) return sub.servers.first;
    state = const ConnectionUi(picking: true);
    final delays = await ref.read(pingsProvider.notifier).pingAll(sub);
    final best = sub.servers.where((s) => delays[s.name] != null).toList()
      ..sort((a, b) => delays[a.name]!.compareTo(delays[b.name]!));
    return best.firstOrNull ?? sub.servers.firstOrNull;
  }

  bool _connecting = false;

  /// One connect at a time: taps and setting changes that land while one runs are dropped, the
  /// running one already uses the latest settings it read.
  Future<void> connect() async {
    if (_connecting) return;
    _connecting = true;
    try {
      await _connect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connect() async {
    final sub = ref.read(activeSubscriptionProvider);
    if (sub == null || sub.servers.isEmpty) {
      state = const ConnectionUi(error: 'Нет серверов');
      return;
    }
    try {
      if (!await Native.prepareVpn()) {
        state = const ConnectionUi(error: 'Нужно разрешение на VPN');
        return;
      }
      await Native.requestNotifications();
      final server = await _pick(sub);
      if (server == null) return;
      state = const ConnectionUi();
      final boot = ref.read(bootProvider);
      final settings = ref.read(settingsProvider);
      final notes = <String>[];
      final config = buildXrayConfig(
        server: server,
        settings: settings,
        logPath: boot.logPath,
        ruCidrs: boot.ruCidrs,
        geo: boot.geo,
        notes: notes,
      );
      final panelRouting = settings.subscriptionRouting && server.routing != null;
      await Native.start(
        xrayConfig: jsonEncode(config),
        vpn: vpnOptions(settings, serverName: server.name, notes: notes),
        fallback: panelRouting
            ? jsonEncode(
                buildXrayConfig(
                  server: server,
                  settings: settings.copyWith(subscriptionRouting: false),
                  logPath: boot.logPath,
                  ruCidrs: boot.ruCidrs,
                ),
              )
            : null,
      );
    } on Object catch (e) {
      state = ConnectionUi(error: e.toString());
    }
  }

  /// A server tapped in the list: remembered, and switched to at once if the tunnel is up.
  Future<void> choose(Subscription sub, String? serverName) async {
    await ref.read(settingsProvider.notifier).selectServer(sub.id, serverName);
    await reconnectIfConnected();
  }
}

/// The server the tunnel runs on, for the home screen; while disconnected, the one it would use.
final currentServerProvider = Provider<({String? name, bool auto})>((ref) {
  final sub = ref.watch(activeSubscriptionProvider);
  final status = ref.watch(vpnStatusProvider).value;
  final picked = sub == null ? null : ref.watch(settingsProvider.select((s) => s.selectedServers[sub.id]));
  if (status != null && status.state != VpnState.disconnected && status.server != null) {
    return (name: status.server, auto: picked == null);
  }
  return (name: picked, auto: picked == null);
});

