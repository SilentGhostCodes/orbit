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
