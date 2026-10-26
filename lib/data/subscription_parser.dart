import 'dart:convert';

import 'package:orbit/data/models.dart';

/// What the panel says about a subscription in its response headers.
class SubscriptionInfo {
  const SubscriptionInfo({this.title, this.upload = 0, this.download = 0, this.total = 0, this.expire, this.updateHours});

  final String? title;
  final int upload;
  final int download;
  final int total;
  final DateTime? expire;
  final int? updateHours;

  /// `subscription-userinfo: upload=…; download=…; total=…; expire=…`, `profile-title` (plain or
  /// `base64:…`) and `profile-update-interval` (hours).
  factory SubscriptionInfo.fromHeaders(Map<String, String> headers) {
    final h = {for (final e in headers.entries) e.key.toLowerCase(): e.value};
    final info = <String, int>{};
    for (final part in (h['subscription-userinfo'] ?? '').split(';')) {
      final kv = part.split('=');
      if (kv.length == 2) {
        final v = num.tryParse(kv[1].trim());
        if (v != null) info[kv[0].trim().toLowerCase()] = v.toInt();
      }
    }
    String? title = h['profile-title']?.trim();
    if (title != null && title.startsWith('base64:')) {
      try {
        title = utf8.decode(base64.decode(base64.normalize(title.substring(7))));
      } on FormatException {
        title = null;
      }
    }
    final expire = info['expire'];
    return SubscriptionInfo(
      title: title == null || title.isEmpty ? null : title,
      upload: info['upload'] ?? 0,
      download: info['download'] ?? 0,
      total: info['total'] ?? 0,
      // 0 and far-future dates mean "never"
      expire: expire == null || expire <= 0 || expire > 4102444800 ? null : DateTime.fromMillisecondsSinceEpoch(expire * 1000),
      updateHours: int.tryParse(h['profile-update-interval']?.trim() ?? ''),
    );
  }
}

const _proxyProtocols = {'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria', 'wireguard', 'socks', 'http'};

bool _isProxy(Map<String, dynamic> o) => _proxyProtocols.contains(o['protocol']);

/// Xray JSON as Remnawave or Marzban send it: a list of full configs, one per server, or a single
/// config. Null when [body] is not Xray JSON (share links, base64, anything else).
List<Server>? parseXrayJson(String body) {
  final trimmed = body.trim();
  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) return null;
  final Object? json;
  try {
    json = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  final configs = switch (json) {
    final List<dynamic> list => list.whereType<Map<String, dynamic>>().toList(),
    final Map<String, dynamic> map => [map],
    _ => const <Map<String, dynamic>>[],
  };
  final servers = <Server>[];
  for (final (i, config) in configs.indexed) {
    final outbounds = (config['outbounds'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
    if (!outbounds.any(_isProxy)) continue;
    final remarks = config['remarks']?.toString().trim();
    if (remarks != null && remarks.isNotEmpty || configs.length > 1) {
      // a full config for one server
      final server = serverFromOutbounds(remarks?.isNotEmpty ?? false ? remarks! : 'Сервер ${i + 1}', outbounds);
      if (server != null) servers.add(server);
    } else {
      // a bare node list: every proxy outbound is a server of its own
      for (final o in outbounds.where(_isProxy)) {
        final server = serverFromOutbounds((o['tag'] ?? 'Сервер ${servers.length + 1}').toString(), [
          o,
          ...outbounds.where((x) => !_isProxy(x)),
        ]);
        if (server != null) servers.add(server);
      }
    }
  }
  return servers.isEmpty ? null : servers;
}

/// Puts the outbound that reaches the server first and tags it "proxy"; the others (a fragment
/// chain the proxy dials through, the panel's direct/block) follow untouched.
Server? serverFromOutbounds(String name, List<Map<String, dynamic>> outbounds) {
  final proxyIndex = outbounds.indexWhere((o) => o['tag'] == 'proxy' && _isProxy(o));
  final index = proxyIndex >= 0 ? proxyIndex : outbounds.indexWhere(_isProxy);
  if (index < 0) return null;
  final proxy = Map<String, dynamic>.of(outbounds[index]);
  final oldTag = proxy['tag'];
  proxy['tag'] = 'proxy';
  final rest = [
    for (final (i, o) in outbounds.indexed)
      if (i != index && o['tag'] != 'proxy') _retarget(o, oldTag),
  ];
  return Server(name: name, outbounds: [proxy, ...rest]);
}

/// Another outbound that dialled through the proxy under its old tag keeps doing so.
Map<String, dynamic> _retarget(Map<String, dynamic> outbound, Object? oldTag) {
  final stream = outbound['streamSettings'];
  if (oldTag == null || stream is! Map<String, dynamic>) return outbound;
  final sockopt = stream['sockopt'];
  if (sockopt is! Map<String, dynamic> || sockopt['dialerProxy'] != oldTag) return outbound;
  return {
    ...outbound,
    'streamSettings': {
      ...stream,
      'sockopt': {...sockopt, 'dialerProxy': 'proxy'},
    },
  };
}

/// Outbounds from libXray's share link conversion: one server each, named by its tag.
List<Server> serversFromLinkOutbounds(List<Map<String, dynamic>> outbounds) {
  final servers = <Server>[];
  for (final (i, o) in outbounds.indexed) {
    final name = (o['tag'] ?? '').toString().trim();
    final server = serverFromOutbounds(name.isEmpty ? 'Сервер ${i + 1}' : name, [o]);
    if (server != null) servers.add(server);
  }
  return servers;
}

/// Unique names, since the list and the saved selection go by name.
List<Server> dedupeNames(List<Server> servers) {
  final seen = <String, int>{};
  return [
    for (final s in servers)
      () {
        final n = seen.update(s.name, (v) => v + 1, ifAbsent: () => 1);
        return n == 1 ? s : Server(name: '${s.name} ($n)', outbounds: s.outbounds);
      }(),
  ];
}
