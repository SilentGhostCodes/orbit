import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum RoutingMode {
  /// Russian sites and addresses go direct.
  bypassRu,

  /// Everything through the server.
  all,
}

enum AppsMode {
  /// Every app goes through the tunnel.
  all,

  /// Only the picked apps.
  include,

  /// All apps but the picked ones.
  exclude,
}

/// The connect button's look, picked under Оформление.
enum PowerButtonStyle {
  /// A still button with an orbit turning round it.
  orbit,

  /// The disc that opens into an eight-petal flower.
  flower;

  String get label => switch (this) {
    orbit => 'Орбита',
    flower => 'Ромашка',
  };
}

/// How servers are pinged, under Пинг.
enum PingType {
  /// An HTTP GET of the test URL through the server.
  proxyGet,

  /// The same with HEAD: no body.
  proxyHead,

  /// Time to open a TCP connection to the server's port.
  tcp,

  /// An ICMP echo to the server's address.
  icmp;

  bool get viaProxy => this == proxyGet || this == proxyHead;

  String get label => switch (this) {
    proxyGet => 'via Proxy GET',
    proxyHead => 'via Proxy HEAD',
    tcp => 'TCP',
    icmp => 'ICMP',
  };
}

/// How many requests a ping through the proxy makes and over what.
enum PingMode {
  /// One request.
  normal('default', 'Default'),

  /// Two requests on fresh connections, the better counts.
  double('double', 'Double'),

  /// Two requests over one kept-alive connection, the better counts.
  keepAlive('keepalive', 'KeepAlive');

  const PingMode(this.id, this.label);

  /// The name libXray's OrbitPing takes.
  final String id;
  final String label;
}

const defaultPingUrl = 'https://www.gstatic.com/generate_204';

/// How the TLS fragmentation hop cuts packets: Xray freedom's `fragment` settings.
class Fragment {
  const Fragment({this.packets = 'tlshello', this.length = '100-200', this.interval = '10-20'});

  /// "tlshello" (only the ClientHello) or a range of packet numbers from the start, like "1-3".
  final String packets;

  /// Bytes per piece, a number or a range.
  final String length;

  /// Milliseconds between pieces, a number or a range.
  final String interval;

  static const defaults = Fragment();

  Map<String, dynamic> toJson() => {'packets': packets, 'length': length, 'interval': interval};

  factory Fragment.fromJson(Object? j) {
    if (j is! Map) return defaults;
    String field(String key, String fallback, bool Function(String) valid) {
      final v = j[key]?.toString().trim() ?? '';
      return valid(v) ? v : fallback;
    }

    return Fragment(
      packets: field('packets', defaults.packets, validPackets),
      length: field('length', defaults.length, validRange),
      interval: field('interval', defaults.interval, validRange),
    );
  }

  /// "N" or "N-M" with N ≤ M.
  static bool validRange(String v) {
    final m = RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$').firstMatch(v.trim());
    if (m == null) return false;
    final a = int.parse(m[1]!);
    final b = m[2] == null ? a : int.parse(m[2]!);
    return a <= b;
  }

  static bool validPackets(String v) => v.trim() == 'tlshello' || (validRange(v) && !v.trim().startsWith('0'));

  @override
  bool operator ==(Object other) =>
      other is Fragment && other.packets == packets && other.length == length && other.interval == interval;

  @override
  int get hashCode => Object.hash(packets, length, interval);
}

/// A DNS server: DNS over HTTPS through the tunnel, and its plain IP for the parts of the system
/// that need one (the VPN's announced resolver, the core's own lookups).
class DnsChoice {
  const DnsChoice(this.id, this.label, this.subtitle, this.doh, this.ip);

  final String id;
  final String label;
  final String subtitle;
  final String doh;
  final String ip;

  static const all = [
    DnsChoice('cloudflare', '1.1.1.1', 'Cloudflare', 'https://1.1.1.1/dns-query', '1.1.1.1'),
    DnsChoice('google', '8.8.8.8', 'Google', 'https://8.8.8.8/dns-query', '8.8.8.8'),
    DnsChoice('quad9', '9.9.9.9', 'Quad9', 'https://9.9.9.9/dns-query', '9.9.9.9'),
    DnsChoice('adguard', 'AdGuard', 'Блокирует рекламу', 'https://94.140.14.14/dns-query', '94.140.14.14'),
  ];

  static DnsChoice byId(String? id) => all.firstWhere((d) => d.id == id, orElse: () => all.first);
}

/// The DNS qWDTT's client looks VK up with (its -go-dns), under Настройки → qWDTT.
enum QwdttDns {
  yandex('yandex', 'Яндекс'),
  cloudflare('cloudflare', 'Cloudflare'),
  google('google', 'Google'),
  dohYandex('doh-yandex', 'Яндекс DoH');

  const QwdttDns(this.id, this.label);

  final String id;
  final String label;

  static QwdttDns byId(String? id) => values.firstWhere((d) => d.id == id, orElse: () => yandex);
}

class OrbitSettings {
  const OrbitSettings({
    this.routing = RoutingMode.bypassRu,
    this.dns = 'cloudflare',
    this.fragment = false,
    this.autoConnect = false,
    this.killSwitch = false,
    this.appsMode = AppsMode.all,
    this.apps = const {},
    this.debugLog = false,
    this.activeSubscription,
    this.selectedServers = const {},
    this.buttonStyle = PowerButtonStyle.orbit,
    this.accent = 0xFF3DD6A0,
    this.pingType = PingType.proxyGet,
    this.pingMode = PingMode.normal,
    this.pingTimeout = 5,
    this.pingUrl = defaultPingUrl,
    this.fragmentSettings = Fragment.defaults,
    this.subscriptionRouting = true,
    this.qwdttDns = 'yandex',
  });

  final RoutingMode routing;
  final String dns;
  final bool fragment;
  final bool autoConnect;

  /// What the user set the Kill Switch row to; Android does the blocking itself.
  final bool killSwitch;
  final AppsMode appsMode;
  final Set<String> apps;
  final bool debugLog;
  final String? activeSubscription;

  /// Picked server per subscription id; a missing entry means "Авто".
  final Map<String, String> selectedServers;

  final PowerButtonStyle buttonStyle;

  /// The accent colour, ARGB, picked under Оформление.
  final int accent;

  final PingType pingType;

  /// For pings through the proxy only.
  final PingMode pingMode;

  /// Seconds, 5–15.
  final int pingTimeout;
  final String pingUrl;

  /// How fragmentation cuts packets when [fragment] is on.
  final Fragment fragmentSettings;

  /// Use the routing and DNS a server's Xray JSON brings, instead of [routing], where it has them.
  final bool subscriptionRouting;

  /// The DNS qWDTT's client finds VK with ([QwdttDns] ids); Яндекс answers on whitelisted mobile.
  final String qwdttDns;

  /// The fragmentation to apply, or null when it is off.
  Fragment? get fragmentOptions => fragment ? fragmentSettings : null;

  DnsChoice get dnsChoice => DnsChoice.byId(dns);

  OrbitSettings copyWith({
    RoutingMode? routing,
    String? dns,
    bool? fragment,
    bool? autoConnect,
    bool? killSwitch,
    AppsMode? appsMode,
    Set<String>? apps,
    bool? debugLog,
    String? activeSubscription,
    bool clearActive = false,
    Map<String, String>? selectedServers,
    PowerButtonStyle? buttonStyle,
    int? accent,
    PingType? pingType,
    PingMode? pingMode,
    int? pingTimeout,
    String? pingUrl,
    Fragment? fragmentSettings,
    bool? subscriptionRouting,
    String? qwdttDns,
  }) => OrbitSettings(
    routing: routing ?? this.routing,
    dns: dns ?? this.dns,
    fragment: fragment ?? this.fragment,
    autoConnect: autoConnect ?? this.autoConnect,
    killSwitch: killSwitch ?? this.killSwitch,
    appsMode: appsMode ?? this.appsMode,
    apps: apps ?? this.apps,
    debugLog: debugLog ?? this.debugLog,
    activeSubscription: clearActive ? null : (activeSubscription ?? this.activeSubscription),
    selectedServers: selectedServers ?? this.selectedServers,
    buttonStyle: buttonStyle ?? this.buttonStyle,
    accent: accent ?? this.accent,
    pingType: pingType ?? this.pingType,
    pingMode: pingMode ?? this.pingMode,
    pingTimeout: pingTimeout ?? this.pingTimeout,
    pingUrl: pingUrl ?? this.pingUrl,
    fragmentSettings: fragmentSettings ?? this.fragmentSettings,
    subscriptionRouting: subscriptionRouting ?? this.subscriptionRouting,
    qwdttDns: qwdttDns ?? this.qwdttDns,
  );

  Map<String, dynamic> toJson() => {
    'routing': routing.name,
    'dns': dns,
    'fragment': fragment,
    'autoConnect': autoConnect,
    'killSwitch': killSwitch,
    'appsMode': appsMode.name,
    'apps': apps.toList(),
    'debugLog': debugLog,
    'activeSubscription': activeSubscription,
    'selectedServers': selectedServers,
    'buttonStyle': buttonStyle.name,
    'accent': accent,
    'pingType': pingType.name,
    'pingMode': pingMode.id,
    'pingTimeout': pingTimeout,
    'pingUrl': pingUrl,
    'fragmentSettings': fragmentSettings.toJson(),
    'subscriptionRouting': subscriptionRouting,
    'qwdttDns': qwdttDns,
  };

  factory OrbitSettings.fromJson(Map<String, dynamic> j) => OrbitSettings(
    routing: RoutingMode.values.asNameMap()[j['routing']] ?? RoutingMode.bypassRu,
    dns: j['dns'] as String? ?? 'cloudflare',
    fragment: j['fragment'] as bool? ?? false,
    autoConnect: j['autoConnect'] as bool? ?? false,
    killSwitch: j['killSwitch'] as bool? ?? false,
    appsMode: AppsMode.values.asNameMap()[j['appsMode']] ?? AppsMode.all,
    apps: {...(j['apps'] as List? ?? const []).cast<String>()},
    debugLog: j['debugLog'] as bool? ?? false,
    activeSubscription: j['activeSubscription'] as String?,
    selectedServers: (j['selectedServers'] as Map? ?? const {}).cast<String, String>(),
    buttonStyle: PowerButtonStyle.values.asNameMap()[j['buttonStyle']] ?? PowerButtonStyle.orbit,
    accent: (j['accent'] as num?)?.toInt() ?? 0xFF3DD6A0,
    pingType: PingType.values.asNameMap()[j['pingType']] ?? PingType.proxyGet,
    pingMode: PingMode.values.where((m) => m.id == j['pingMode']).firstOrNull ?? PingMode.normal,
    pingTimeout: ((j['pingTimeout'] as num?)?.toInt() ?? 5).clamp(5, 15),
    pingUrl: j['pingUrl'] as String? ?? defaultPingUrl,
    fragmentSettings: Fragment.fromJson(j['fragmentSettings']),
    subscriptionRouting: j['subscriptionRouting'] as bool? ?? true,
    qwdttDns: QwdttDns.byId(j['qwdttDns'] as String?).id,
  );

  static const _key = 'orbit_settings';

  static Future<OrbitSettings> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const OrbitSettings();
    try {
      return OrbitSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const OrbitSettings();
    }
  }

  Future<void> save() async => (await SharedPreferences.getInstance()).setString(_key, jsonEncode(toJson()));
}
