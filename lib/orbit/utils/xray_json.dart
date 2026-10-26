/// Xray JSON subscriptions (what Remnawave and Marzban send to Happ or v2rayNG).
///
/// Hiddify's core reads any JSON as a sing-box config, so an Xray JSON subscription used to come out as
/// broken servers. Orbit wraps each Xray config, untouched, in an `xray` outbound: Orbit's build of
/// the core runs it in xray-core (see core/xray), so CDN, XHTTP extra/xmux/downloadSettings and fragment
/// chains work exactly as the panel wrote them.
library;

import 'dart:convert';
import 'dart:io';

/// The subscription as a sing-box config of `xray` outbounds, or null when [content] is not Xray JSON.
String? xrayJsonToSingbox(String content) {
  final trimmed = content.trim();
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
  if (!configs.any(isXrayConfig)) return null;

  final outbounds = <Map<String, dynamic>>[];
  final used = <String>{};
  for (final (i, config) in configs.indexed) {
    if (!isXrayConfig(config) || proxyOutbound(config) == null) continue;
    var tag = (config['remarks'] ?? 'Server ${i + 1}').toString().trim();
    if (tag.isEmpty) tag = 'Server ${i + 1}';
    // sing-box needs unique tags; panels repeat names across protocols
    final base = tag;
    for (var n = 2; used.contains(tag); n++) {
      tag = '$base $n';
    }
    used.add(tag);
    outbounds.add({'type': 'xray', 'tag': tag, 'xconfig': config});
  }
  if (outbounds.isEmpty) return null;
  return const JsonEncoder.withIndent('  ').convert({'outbounds': outbounds});
}

const _proxyProtocols = {'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria', 'wireguard', 'socks', 'http'};

/// An Xray config (as opposed to a sing-box one): its outbounds say "protocol", not "type".
bool isXrayConfig(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  return outbounds is List && outbounds.whereType<Map<String, dynamic>>().any((o) => o['protocol'] is String);
}

/// The outbound that carries the traffic: the one tagged "proxy", else the first that goes to a server.
Map<String, dynamic>? proxyOutbound(Map<String, dynamic> config) {
  final outbounds = (config['outbounds'] as List? ?? const []).whereType<Map<String, dynamic>>();
  return outbounds.where((o) => o['tag'] == 'proxy' && _proxyProtocols.contains(o['protocol'])).firstOrNull ??
      outbounds.where((o) => _proxyProtocols.contains(o['protocol'])).firstOrNull;
}

/// What the server list shows for an Xray config: protocol, transport, and whether it is REALITY.
({String protocol, String? network, bool reality}) describeXrayConfig(Map<String, dynamic> config) {
  final proxy = proxyOutbound(config);
  final stream = proxy?['streamSettings'] is Map<String, dynamic>
      ? proxy!['streamSettings'] as Map<String, dynamic>
      : const <String, dynamic>{};
  return (
    protocol: (proxy?['protocol'] ?? 'xray').toString(),
    network: stream['network']?.toString(),
    reality: stream['security'] == 'reality',
  );
}

/// Rewrites a downloaded subscription file in place when it is Xray JSON.
Future<void> convertXrayJsonFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return;
  final converted = xrayJsonToSingbox(await file.readAsString());
  if (converted != null) await file.writeAsString(converted);
}
