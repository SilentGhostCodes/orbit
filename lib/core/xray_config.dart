import 'dart:convert';

import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';

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
const _fragmentOutbound = {
  'tag': 'orbit-fragment',
  'protocol': 'freedom',
  'settings': {
    'fragment': {'packets': 'tlshello', 'length': '100-200', 'interval': '10-20'},
  },
};

/// The server's outbounds, with the fragment hop when it is on and the server has no chain of its own.
List<Map<String, dynamic>> serverOutbounds(Server server, {required bool fragment}) {
  if (!fragment) return server.outbounds;
  final proxy = Map<String, dynamic>.of(server.proxy);
  final stream = Map<String, dynamic>.of(proxy['streamSettings'] as Map<String, dynamic>? ?? const {});
  final sockopt = Map<String, dynamic>.of(stream['sockopt'] as Map<String, dynamic>? ?? const {});
  if (sockopt['dialerProxy'] != null) return server.outbounds;
  sockopt['dialerProxy'] = 'orbit-fragment';
  stream['sockopt'] = sockopt;
  proxy['streamSettings'] = stream;
  return [proxy, ...server.outbounds.skip(1), _fragmentOutbound];
}

/// The config for pinging [server]: just its outbounds; libXray adds the rest.
String pingConfig(Server server, {required bool fragment}) =>
    jsonEncode({'outbounds': serverOutbounds(server, fragment: fragment)});

/// The full config the VPN service runs. The service adds `env: {"xray.tun.fd": …}` once it has
/// the tunnel's descriptor.
///
/// Packets come in through Xray's own tun inbound. DNS sent to the tunnel goes to Xray's DNS, which
/// asks [OrbitSettings.dnsChoice] over HTTPS through the server. The panel's own routing and DNS are
/// not used: they name geoip:/geosite: lists the phone does not have, and Orbit routes by itself.
Map<String, dynamic> buildXrayConfig({
  required Server server,
  required OrbitSettings settings,
  required String logPath,
  required List<String> ruCidrs,
}) {
  final bypassRu = settings.routing == RoutingMode.bypassRu;
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
      ...serverOutbounds(server, fragment: settings.fragment),
      {'tag': 'orbit-direct', 'protocol': 'freedom'},
      {'tag': 'orbit-block', 'protocol': 'blackhole'},
      {'tag': 'orbit-dns', 'protocol': 'dns'},
    ],
    'dns': {
      'servers': [settings.dnsChoice.doh],
      'queryStrategy': 'UseIPv4',
    },
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
        {'inboundTag': ['tun'], 'port': '53', 'outboundTag': 'orbit-dns'},
        {'ip': privateCidrs, 'outboundTag': 'orbit-direct'},
        if (bypassRu) {'domain': ruDomains, 'outboundTag': 'orbit-direct'},
        if (bypassRu && ruCidrs.isNotEmpty) {'ip': ruCidrs, 'outboundTag': 'orbit-direct'},
        // everything else falls through to the first outbound, the server
      ],
    },
  };
}

/// What the VPN service needs besides the Xray config: per-app rules and the DNS to announce.
Map<String, dynamic> vpnOptions(OrbitSettings settings, {required String serverName}) => {
  'appsMode': settings.appsMode.name,
  'apps': settings.apps.toList(),
  'dnsIp': settings.dnsChoice.ip,
  'server': serverName,
  'autoConnect': settings.autoConnect,
};

/// The CIDR lines of an ipverse aggregated list.
List<String> parseCidrList(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
];
