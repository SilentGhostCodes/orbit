import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:orbit/core/libxray.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/subscription_parser.dart';
import 'package:path_provider/path_provider.dart';

class SubscriptionException implements Exception {
  SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads, parses and stores subscriptions.
class SubscriptionRepo {
  SubscriptionRepo(this.userAgent);

  /// Starts with "Orbit/" so a panel rule (Remnawave: `^(?:…|orbit)` → XRAY_JSON) can pick the format.
  final String userAgent;

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/subscriptions.json');

  static Future<List<Subscription>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return [for (final s in list) Subscription.fromJson(s as Map<String, dynamic>)];
    } on Object {
      return [];
    }
  }

  static Future<void> save(List<Subscription> subscriptions) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in subscriptions) s.toJson()]));
    await tmp.rename(file.path);
  }

  /// The servers in a subscription body: Xray JSON as it is, anything else through libXray's share
  /// link parser (plain links, base64, Xray node lists).
  static Future<List<Server>> parseBody(String body) async {
    final xray = parseXrayJson(body);
    if (xray != null) return dedupeNames(xray);
    try {
      return dedupeNames(serversFromLinkOutbounds(await LibXray.convertShareLinks(body.trim())));
    } on LibXrayException {
      throw SubscriptionException('В подписке не нашлось серверов');
    }
  }

  Future<({List<Server> servers, SubscriptionInfo info, String fallbackName})> fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw SubscriptionException('Это не ссылка на подписку');
    }
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: {'User-Agent': userAgent, 'Accept': '*/*'})
          .timeout(const Duration(seconds: 25));
    } on Object catch (e) {
      throw SubscriptionException('Не удалось загрузить подписку: $e');
    }
    if (response.statusCode != 200) {
      throw SubscriptionException('Панель ответила ${response.statusCode}');
    }
    // some panels put a byte order mark in front of the JSON
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).replaceFirst('\uFEFF', '');
    final servers = await parseBody(body);
    return (
      servers: servers,
      info: SubscriptionInfo.fromHeaders(response.headers),
      fallbackName: _nameFromDisposition(response.headers['content-disposition']) ?? uri.host,
    );
  }

  static String? _nameFromDisposition(String? header) {
    if (header == null) return null;
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''', caseSensitive: false).firstMatch(header);
    if (m == null) return null;
    final name = Uri.decodeComponent(m.group(1)!).replaceAll(RegExp(r'\.(txt|json|yaml)$'), '').trim();
    return name.isEmpty ? null : name;
  }
}
