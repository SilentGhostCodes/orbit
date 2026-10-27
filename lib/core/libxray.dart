import 'dart:convert';

import 'package:orbit/core/native.dart';

class LibXrayException implements Exception {
  LibXrayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// libXray's single entry point: `{"apiVersion": 3, "method": …, "payload": …}` in, `{success, data, error}` out.
abstract class LibXray {
  /// The DNS server (an IP) libXray resolves server names with in the app's process; see [Native.libxray].
  static String dns = '1.1.1.1';

  static Future<Object?> _invoke(String method, [Map<String, dynamic> payload = const {}]) async {
    final response = await Native.libxray(
      jsonEncode({'apiVersion': 3, 'method': method, 'payload': payload}),
      dns: dns,
    );
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    if (decoded['success'] != true) throw LibXrayException((decoded['error'] ?? 'libXray: $method failed').toString());
    return decoded['data'];
  }

  /// Share links, or a base64 subscription of them, as Xray outbounds tagged with the server names.
  static Future<List<Map<String, dynamic>>> convertShareLinks(String text) async {
    final data = await _invoke('convertShareLinksToXrayJson', {'text': text}) as Map<String, dynamic>;
    return (data['outbounds'] as List).cast<Map<String, dynamic>>();
  }

  /// Plain text of a subscription body that may be base64.
  static Future<String> decodeSubscription(String text) async {
    final data = await _invoke('decodeSubscriptionText', {'text': text}) as Map<String, dynamic>;
    return data['text'] as String;
  }

  /// libXray takes at most this many configs per pingBatch call.
  static const pingBatchSize = 5;

  /// Round trip through each config's "proxy" outbound, in milliseconds; null where it failed.
  /// At most [pingBatchSize] configs. libXray refuses while it runs a tunnel in the same process,
  /// which is why the VPN has its own.
  static Future<List<int?>> ping(
    List<String> xrayConfigs, {
    int timeoutSeconds = 4,
    String url = 'https://www.gstatic.com/generate_204',
  }) async {
    if (xrayConfigs.isEmpty) return const [];
    final data =
        await _invoke('pingBatch', {
              'configs': [
                for (final c in xrayConfigs) {'xrayJson': c, 'outboundTag': 'proxy'},
              ],
              'timeout': timeoutSeconds,
              'url': url,
            })
            as Map<String, dynamic>;
    return [
      for (final r in (data['results'] as List).cast<Map<String, dynamic>>())
        r['success'] == true ? (r['delay'] as num).toInt() : null,
    ];
  }

  static Future<String> version() async {
    final data = await _invoke('xrayVersion') as Map<String, dynamic>;
    return data['version'] as String? ?? '';
  }
}
