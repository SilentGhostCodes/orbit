import 'package:orbit/util/server_meta.dart';

/// One server: the Xray outbounds that reach it, the one doing so first and tagged "proxy".
/// Anything after it (a fragment chain, the panel's own "direct") stays as the panel wrote it.
class Server {
  const Server({required this.name, required this.outbounds});

  final String name;
  final List<Map<String, dynamic>> outbounds;

  Map<String, dynamic> get proxy => outbounds.first;

  Map<String, dynamic> get _stream =>
      proxy['streamSettings'] is Map<String, dynamic> ? proxy['streamSettings'] as Map<String, dynamic> : const {};

  /// "VLESS Reality", "VLESS XHTTP", "Hysteria2"…
  String get protocol => protocolLabel(
    (proxy['protocol'] ?? '').toString(),
    transport: _stream['network']?.toString(),
    reality: _stream['security'] == 'reality',
  );

  String get displayName => displayNameOf(name);

  /// Where the proxy outbound connects to, for TCP and ICMP pings; null if it does not say.
  ({String host, int port})? get endpoint {
    final settings = proxy['settings'];
    if (settings is! Map) return null;
    ({String host, int port})? from(Object? m) {
      if (m is! Map) return null;
      final host = m['address']?.toString();
      final port = m['port'] is num ? (m['port'] as num).toInt() : int.tryParse('${m['port']}');
      return host == null || host.isEmpty || port == null ? null : (host: host, port: port);
    }

    for (final list in [settings['vnext'], settings['servers']]) {
      if (list is List && list.isNotEmpty) return from(list.first);
    }
    final peers = settings['peers'];
    if (peers is List && peers.isNotEmpty && peers.first is Map) {
      final endpoint = (peers.first as Map)['endpoint']?.toString() ?? '';
      final colon = endpoint.lastIndexOf(':');
      final port = colon < 0 ? null : int.tryParse(endpoint.substring(colon + 1));
      if (port != null) return (host: endpoint.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), ''), port: port);
    }
    return from(settings);
  }

  String? get country => guessCountry(name);

  /// Same server across subscription updates, as far as the list is concerned.
  String get key => name;

  Map<String, dynamic> toJson() => {'name': name, 'outbounds': outbounds};

  factory Server.fromJson(Map<String, dynamic> json) => Server(
    name: json['name'] as String,
    outbounds: (json['outbounds'] as List).cast<Map<String, dynamic>>(),
  );
}

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.servers,
    required this.updatedAt,
    this.url,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire,
    this.autoUpdate = true,
    this.updateHours = 12,
  });

  final String id;
  final String name;

  /// Null for servers pasted by hand.
  final String? url;
  final List<Server> servers;
  final DateTime updatedAt;

  /// From the panel's subscription-userinfo header, in bytes; total 0 is unlimited.
  final int upload;
  final int download;
  final int total;

  /// Null when the panel says nothing or the subscription never expires.
  final DateTime? expire;

  final bool autoUpdate;
  final int updateHours;

  int get used => upload + download;

  bool get needsUpdate =>
      url != null && autoUpdate && DateTime.now().difference(updatedAt) >= Duration(hours: updateHours);

  Subscription copyWith({
    String? name,
    List<Server>? servers,
    DateTime? updatedAt,
    int? upload,
    int? download,
    int? total,
    DateTime? expire,
    bool clearExpire = false,
    bool? autoUpdate,
    int? updateHours,
  }) => Subscription(
    id: id,
    url: url,
    name: name ?? this.name,
    servers: servers ?? this.servers,
    updatedAt: updatedAt ?? this.updatedAt,
    upload: upload ?? this.upload,
    download: download ?? this.download,
    total: total ?? this.total,
    expire: clearExpire ? null : (expire ?? this.expire),
    autoUpdate: autoUpdate ?? this.autoUpdate,
    updateHours: updateHours ?? this.updateHours,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'servers': [for (final s in servers) s.toJson()],
    'updatedAt': updatedAt.toIso8601String(),
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire?.toIso8601String(),
    'autoUpdate': autoUpdate,
    'updateHours': updateHours,
  };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String?,
    servers: [for (final s in json['servers'] as List) Server.fromJson(s as Map<String, dynamic>)],
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    upload: json['upload'] as int? ?? 0,
    download: json['download'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    expire: json['expire'] == null ? null : DateTime.parse(json['expire'] as String),
    autoUpdate: json['autoUpdate'] as bool? ?? true,
    updateHours: json['updateHours'] as int? ?? 12,
  );
}
