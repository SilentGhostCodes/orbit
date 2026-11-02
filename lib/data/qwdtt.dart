import 'dart:convert';

import 'package:orbit/data/models.dart';

/// qWDTT (github.com/kostfuciy/qWDTT): WireGuard through VK call TURN relays, for mobile whitelists.
/// A profile is the user's server (`peer`, its DTLS port), the VK call hashes whose relays carry
/// the traffic, the connection password and how many parallel streams to open.
///
/// In Orbit a profile is a [Server] whose proxy outbound is a placeholder,
/// `{"protocol":"wireguard","settings":{"orbitQwdtt":true,"qwdtt":{…}}}`: the VPN service starts
/// qWDTT's client with the profile and puts the server's WireGuard config in its place.
class QwdttProfile {
  const QwdttProfile({
    required this.name,
    required this.peer,
    required this.hashes,
    required this.password,
    this.workers = defaultWorkers,
    this.port = defaultPort,
  });

  final String name;

  /// host:port of the server's DTLS listener.
  final String peer;

  /// VK call hashes (the part of a vk.com/call/join/… link after "join/"); at most [maxHashes].
  final List<String> hashes;
  final String password;
  final int workers;

  /// Where the client listens on the phone, for WireGuard.
  final int port;

  static const defaultWorkers = 16;
  static const defaultPort = 9000;
  static const maxHashes = 4;
  static const maxWorkers = 108;

  Map<String, dynamic> toJson() => {
    'name': name,
    'peer': peer,
    'hashes': hashes,
    'password': password,
    'workers': workers,
    'port': port,
  };

  factory QwdttProfile.fromJson(Map<String, dynamic> j) => QwdttProfile(
    name: j['name']?.toString() ?? 'qWDTT',
    peer: j['peer']?.toString() ?? '',
    hashes: [for (final h in j['hashes'] as List? ?? const []) h.toString()],
    password: j['password']?.toString() ?? '',
    workers: (j['workers'] as num?)?.toInt() ?? defaultWorkers,
    port: (j['port'] as num?)?.toInt() ?? defaultPort,
  );

  /// The [Server] Orbit lists and connects to.
  Server toServer() => Server(
    name: name,
    outbounds: [
      {
        'tag': 'proxy',
        'protocol': 'wireguard',
        'settings': {'orbitQwdtt': true, 'qwdtt': toJson()},
      },
    ],
  );

  /// The profile behind [server], if it is a qWDTT one.
  static QwdttProfile? of(Server server) {
    final settings = server.proxy['settings'];
    if (settings is! Map || settings['orbitQwdtt'] != true || settings['qwdtt'] is! Map) return null;
    return QwdttProfile.fromJson(Map<String, dynamic>.from(settings['qwdtt'] as Map));
  }
}

class QwdttException implements Exception {
  const QwdttException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class Qwdtt {
  static final _scheme = RegExp(r'^(?:q?wdtt)://', caseSensitive: false);

  /// `wdtt://…`, `qwdtt://…`, or a profile or subscription as JSON (also base64 of it, as QR codes
  /// carry it).
  static bool matches(String text) {
    final t = text.trim();
    return _scheme.hasMatch(t) || _json(t) != null;
  }

  /// The profiles in [text]: one for a link or a profile, several for a subscription's JSON.
  /// Throws [QwdttException] if it is qWDTT but broken; null if it is not qWDTT at all.
  static ({String? name, List<QwdttProfile> profiles})? parse(String text) {
    final t = text.trim();
    if (RegExp(r'^wdtt://', caseSensitive: false).hasMatch(t)) return (name: null, profiles: [_wdtt(t)]);
    if (RegExp(r'^qwdtt://', caseSensitive: false).hasMatch(t)) return (name: null, profiles: [_qwdtt(t)]);
    final json = _json(t);
    if (json == null) return null;
    if (json['profiles'] is List) {
      final profiles = <QwdttProfile>[];
      for (final (i, p) in (json['profiles'] as List).indexed) {
        if (p is Map) profiles.add(_profile(Map<String, dynamic>.from(p), fallbackName: 'qWDTT ${i + 1}'));
      }
      if (profiles.isEmpty) throw const QwdttException('В подписке qWDTT нет профилей');
      final name = (json['subscriptionName'] ?? json['name'])?.toString().trim();
      return (name: name == null || name.isEmpty ? null : name, profiles: profiles);
    }
    return (name: null, profiles: [_profile(json, fallbackName: 'qWDTT')]);
  }

  /// `wdtt://host:dtlsPort:wgPort:localPort:password:hash` (the original WDTT app's links).
  static QwdttProfile _wdtt(String link) {
    final body = Uri.decodeComponent(link.substring('wdtt://'.length).split('#').first).trim();
    final parts = body.split(':');
    // an IPv6 host would be bracketed: [::1]:56000:…
    if (parts.length < 6) throw const QwdttException('Ссылка wdtt:// неполная');
    final hash = parts.removeLast();
    final password = parts.removeLast();
    final localPort = int.tryParse(parts.removeLast());
    parts.removeLast(); // the server's WireGuard port: the server tells it itself
    final dtlsPort = int.tryParse(parts.removeLast());
    final host = parts.join(':');
    if (host.isEmpty || dtlsPort == null) throw const QwdttException('В ссылке wdtt:// нет адреса сервера');
    return _checked(
      QwdttProfile(
        name: host,
        peer: '$host:$dtlsPort',
        hashes: [hash],
        password: password,
        port: localPort ?? QwdttProfile.defaultPort,
      ),
    );
  }

  /// `qwdtt://config?name=…&peer=host:port&hashes=a,b&workers=18&port=9000&pass=…`.
  static QwdttProfile _qwdtt(String link) {
    final Uri uri;
    try {
      uri = Uri.parse(link.trim());
    } on FormatException {
      throw const QwdttException('Ссылка qwdtt:// повреждена');
    }
    final q = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value};
    return _profile(q, fallbackName: 'qWDTT');
  }

  /// A profile from JSON or query parameters; qWDTT accepts several spellings of each key.
  static QwdttProfile _profile(Map<String, dynamic> j, {required String fallbackName}) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return null;
    }

    final hashesRaw = j['hashes'] ?? j['hash'] ?? j['vk'] ?? j['vkHashes'];
    final hashes = switch (hashesRaw) {
      final List<dynamic> list => [for (final h in list) h.toString()],
      final Object v => v.toString().split(','),
      null => const <String>[],
    };
    final peer = pick(['peer', 'server', 'address', 'host']) ?? '';
    final port = pick(['dtlsPort', 'dtls_port']);
    return _checked(
      QwdttProfile(
        name: pick(['name', 'title', 'remark', 'remarks']) ?? fallbackName,
        peer: port != null && !peer.contains(':') ? '$peer:$port' : peer,
        hashes: hashes,
        password: pick(['pass', 'password', 'connectionPassword', 'key']) ?? '',
        workers: int.tryParse(pick(['workers', 'n', 'streams']) ?? '') ?? QwdttProfile.defaultWorkers,
        port: int.tryParse(pick(['port', 'localPort', 'local_port']) ?? '') ?? QwdttProfile.defaultPort,
      ),
    );
  }

  /// [p] cleaned up (hashes out of call links, limits) and checked; throws [QwdttException].
  static QwdttProfile validated(QwdttProfile p) => _checked(p);

  static QwdttProfile _checked(QwdttProfile p) {
    // unique, in order; what is not a hash left out
    final hashes = <String>{for (final h in p.hashes) ?_hash(h)}.toList();
    if (p.peer.isEmpty || !p.peer.contains(':')) throw const QwdttException('В профиле qWDTT нет адреса сервера');
    if (hashes.isEmpty) throw const QwdttException('В профиле qWDTT нет хешей звонков ВК');
    if (p.password.isEmpty) throw const QwdttException('В профиле qWDTT нет пароля');
    final port = p.port.clamp(1024, 65535);
    return QwdttProfile(
      name: p.name.trim().isEmpty ? p.peer : p.name.trim(),
      peer: p.peer,
      hashes: hashes.take(QwdttProfile.maxHashes).toList(),
      password: p.password,
      workers: p.workers.clamp(1, QwdttProfile.maxWorkers),
      port: port,
    );
  }

  /// A hash, also out of a whole call link (`vk.com/call/join/<hash>`).
  static String? _hash(String raw) {
    var h = raw.trim();
    final join = h.indexOf('/join/');
    if (join >= 0) h = h.substring(join + 6);
    h = h.split(RegExp(r'[?#/\s]')).first;
    return RegExp(r'^[A-Za-z0-9_\-]{8,128}$').hasMatch(h) ? h : null;
  }

  /// [text] as a JSON object that looks like qWDTT, directly or base64-wrapped.
  static Map<String, dynamic>? _json(String text) {
    Map<String, dynamic>? decode(String s) {
      final t = s.trim();
      if (!t.startsWith('{')) return null;
      try {
        final j = jsonDecode(t);
        if (j is! Map<String, dynamic>) return null;
        final looks = j['profiles'] is List ||
            ((j.containsKey('peer') || j.containsKey('server')) && (j.containsKey('hashes') || j.containsKey('hash')));
        return looks ? j : null;
      } on FormatException {
        return null;
      }
    }

    final direct = decode(text);
    if (direct != null || text.length > 64 * 1024) return direct;
    if (!RegExp(r'^[A-Za-z0-9+/=_\-\s]{16,}$').hasMatch(text)) return null;
    try {
      final clean = text.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
      return decode(utf8.decode(base64.decode(base64.normalize(clean)), allowMalformed: false));
    } on FormatException {
      return null;
    }
  }
}
