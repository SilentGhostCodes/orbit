import 'dart:convert';

import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/util/format.dart';

/// Addresses that never go through the tunnel.
const privateCidrs = [
  '0.0.0.0/8',
  '10.0.0.0/8',
  '100.64.0.0/10',
  '127.0.0.0/8',
  '169.254.0.0/16',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '224.0.0.0/4',
  '255.255.255.255/32',
  '::1/128',
  'fc00::/7',
  'fe80::/10',
];

/// Russian top-level domains, for "Обход RU": .ru, .su, .рф.
const ruDomains = ['domain:ru', 'domain:su', 'domain:xn--p1ai'];

/// The proxy dials through this when TLS fragmentation is on: the ClientHello is cut into pieces
/// so DPI looking for the SNI does not see it whole.
Map<String, dynamic> _fragmentOutbound(Fragment f) => {
  'tag': 'orbit-fragment',
  'protocol': 'freedom',
  'settings': {'fragment': f.toJson()},
};

/// The server's outbounds, with the fragment hop when [fragment] is given and the server has no
/// chain of its own.
List<Map<String, dynamic>> serverOutbounds(Server server, {required Fragment? fragment}) {
  if (fragment == null) return server.outbounds;
  final proxy = Map<String, dynamic>.of(server.proxy);
  final stream = Map<String, dynamic>.of(proxy['streamSettings'] as Map<String, dynamic>? ?? const {});
  final sockopt = Map<String, dynamic>.of(stream['sockopt'] as Map<String, dynamic>? ?? const {});
  if (sockopt['dialerProxy'] != null) return server.outbounds;
  sockopt['dialerProxy'] = 'orbit-fragment';
  stream['sockopt'] = sockopt;
  proxy['streamSettings'] = stream;
  return [proxy, ...server.outbounds.skip(1), _fragmentOutbound(fragment)];
}

/// The config for pinging [server]: just its outbounds; libXray adds the rest.
String pingConfig(Server server, {required Fragment? fragment}) =>
    jsonEncode({'outbounds': serverOutbounds(server, fragment: fragment)});

/// The geosite:/geoip: codes the APK's lists have (assets/xray/*.txt, written in CI).
class GeoCodes {
  const GeoCodes({this.site = const {}, this.ip = const {}});

  final Set<String> site;
  final Set<String> ip;

  factory GeoCodes.parse(String site, String ip) => GeoCodes(site: _lines(site), ip: _lines(ip));

  static Set<String> _lines(String text) => {
    for (final l in const LineSplitter().convert(text))
      if (l.trim().isNotEmpty) l.trim().toLowerCase(),
  };

  /// Whether Xray can resolve [entry] of a domain or IP list. Anything that is not a geo list
  /// (a domain, a CIDR) is fine; ext: files are not shipped.
  bool has(String entry) {
    final e = entry.trim().toLowerCase();
    if (e.startsWith('geosite:')) return site.contains(e.substring(8).split('@').first);
    if (e.startsWith('geoip:')) return ip.contains(e.substring(6).replaceFirst('!', ''));
    return !e.startsWith('ext:') && !e.startsWith('ext-domain:') && !e.startsWith('ext-ip:');
  }
}

/// A geo list field of a rule: what Xray can load, or null if missing lists emptied it.
List<dynamic>? _geoFiltered(List<dynamic> list, GeoCodes geo, Set<String> missing) {
  final kept = <dynamic>[];
  for (final e in list) {
    if (e is String && !geo.has(e)) {
      missing.add(e);
    } else {
      kept.add(e);
    }
  }
  return kept.isEmpty && list.isNotEmpty ? null : kept;
}

/// [object] with its geo list [fields] filtered, or null when one of them lost everything: a
/// rule's fields all have to match, so it is dropped rather than widened.
Map<String, dynamic>? _withoutMissing(
  Map<String, dynamic> object,
  List<String> fields,
  GeoCodes geo,
  Set<String> missing,
) {
  final out = Map<String, dynamic>.of(object);
  for (final f in fields) {
    final value = object[f];
    if (value is! List) continue;
    final kept = _geoFiltered(value, geo, missing);
    if (kept == null) return null;
    out[f] = kept;
  }
  return out;
}

/// The panel's rules without those naming lists the APK lacks.
List<Map<String, dynamic>> _panelRules(Object? rules, GeoCodes geo, Set<String> missing) {
  final out = <Map<String, dynamic>>[];
  if (rules is! List) return out;
  for (final r in rules.whereType<Map<String, dynamic>>()) {
    final rule = _withoutMissing(r, const ['domain', 'domains', 'ip', 'source', 'sourceIP'], geo, missing);
    if (rule != null) out.add(rule);
  }
  return out;
}

/// The panel's DNS the same way: a server limited to missing lists is dropped, not opened up.
Map<String, dynamic> _panelDns(Map<String, dynamic> dns, GeoCodes geo, Set<String> missing) {
  final out = Map<String, dynamic>.of(dns);
  final servers = dns['servers'];
  if (servers is List) {
    out['servers'] = [
      for (final s in servers)
        if (s is Map<String, dynamic>)
          ?_withoutMissing(s, const ['domains', 'expectIPs', 'expectedIPs', 'unexpectedIPs'], geo, missing)
        else
          s,
    ];
  }
  final hosts = dns['hosts'];
  if (hosts is Map) {
    final kept = <String, dynamic>{};
    for (final e in hosts.entries) {
      final key = e.key.toString();
      if (geo.has(key)) {
        kept[key] = e.value;
      } else {
        missing.add(key);
      }
    }
    out['hosts'] = kept;
  }
  return out;
}

/// The full config the VPN service runs. The service adds `env: {"xray.tun.fd": …,
/// "xray.location.asset": …}` once it has the tunnel's descriptor and the geo files.
///
/// Packets come in through Xray's own tun inbound, and DNS sent to the tunnel goes to Xray's DNS.
/// With [OrbitSettings.subscriptionRouting] on and a server whose Xray JSON had them, the panel's
/// routing and DNS decide the rest (rules naming lists the APK lacks are left out and reported in
/// [notes]); otherwise Orbit's own [OrbitSettings.routing], with DNS asked of
/// [OrbitSettings.dnsChoice] over HTTPS through the server.
Map<String, dynamic> buildXrayConfig({
  required Server server,
  required OrbitSettings settings,
  required String logPath,
  required List<String> ruCidrs,
  GeoCodes geo = const GeoCodes(),
  List<String>? notes,
}) {
  final panel = settings.subscriptionRouting && server.routing != null;
  final bypassRu = settings.routing == RoutingMode.bypassRu;
  final missing = <String>{};
  final ownRules = [
    {
      'inboundTag': ['tun'],
      'port': '53',
      'outboundTag': 'orbit-dns',
    },
    {'ip': privateCidrs, 'outboundTag': 'orbit-direct'},
  ];
  final Map<String, dynamic> routing;
  final Map<String, dynamic> dns;
  if (panel) {
    routing = {
      ...server.routing!,
      'rules': [...ownRules, ..._panelRules(server.routing!['rules'], geo, missing)],
    };
    dns = server.dns == null ? _ownDns(settings) : _panelDns(server.dns!, geo, missing);
    final count = (routing['rules'] as List).length - ownRules.length;
    notes?.add('роутинг подписки: $count ${plural(count, 'правило', 'правила', 'правил')}');
    if (missing.isNotEmpty) notes?.add('роутинг подписки: нет списков ${missing.join(', ')}, правила с ними пропущены');
  } else {
    routing = {
      'domainStrategy': 'AsIs',
      'rules': [
        ...ownRules,
        if (bypassRu) {'domain': ruDomains, 'outboundTag': 'orbit-direct'},
        if (bypassRu && ruCidrs.isNotEmpty) {'ip': ruCidrs, 'outboundTag': 'orbit-direct'},
        // everything else falls through to the first outbound, the server
      ],
    };
    dns = _ownDns(settings);
  }
  return {
    'log': {'loglevel': settings.debugLog ? 'debug' : 'warning', 'error': logPath, 'access': 'none'},
    'inbounds': [
      {
        'tag': 'tun',
        'protocol': 'tun',
        'port': 0,
        'settings': {'name': 'orbit', 'mtu': 1500},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': true,
        },
      },
    ],
    'outbounds': [
      ...serverOutbounds(server, fragment: settings.fragmentOptions),
      {'tag': 'orbit-direct', 'protocol': 'freedom'},
      {'tag': 'orbit-block', 'protocol': 'blackhole'},
      {'tag': 'orbit-dns', 'protocol': 'dns'},
    ],
    'dns': dns,
    'routing': routing,
  };
}

Map<String, dynamic> _ownDns(OrbitSettings settings) => {
  'servers': [settings.dnsChoice.doh],
  'queryStrategy': 'UseIPv4',
};

/// What the VPN service needs besides the Xray config: per-app rules and the DNS to announce.
Map<String, dynamic> vpnOptions(OrbitSettings settings, {required String serverName, List<String> notes = const []}) => {
  'appsMode': settings.appsMode.name,
  'apps': settings.apps.toList(),
  'dnsIp': settings.dnsChoice.ip,
  'server': serverName,
  'autoConnect': settings.autoConnect,
  'notes': notes,
};

/// The CIDR lines of an ipverse aggregated list.
List<String> parseCidrList(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
];
