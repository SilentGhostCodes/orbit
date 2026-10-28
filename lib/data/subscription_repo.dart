import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:orbit/core/libxray.dart';
import 'package:orbit/data/device.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/subscription_parser.dart';
import 'package:orbit/data/wrapped_link.dart';
import 'package:path_provider/path_provider.dart';

class SubscriptionException implements Exception {
  SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads, parses and stores subscriptions.
class SubscriptionRepo {
  SubscriptionRepo(this.userAgent, {this.device});

  /// Starts with "Orbit/" so a panel rule (Remnawave: `^(?:…|orbit)` → XRAY_JSON) can pick the format.
  final String userAgent;

  /// Sent as Remnawave's device headers (HWID).
  final DeviceInfo? device;

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

  static const _timeout = Duration(seconds: 25);
  static const _maxRedirects = 5;

  /// How many wrapped links (pages → happ:// → URL → …) one fetch follows before giving up.
  static const _maxUnwraps = 3;

  /// Downloads [url]. Redirect pages are followed through: an HTTP redirect to `happ://…`, or a web
  /// page that opens Happ with an encrypted link, lead to the subscription inside. `url` in the
  /// result is the one to store and refresh: [url] itself, or the subscription a wrapped link held.
  Future<({List<Server> servers, SubscriptionInfo info, String fallbackName, String url})> fetch(
    String url, {
    int unwraps = 0,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw SubscriptionException('Это не ссылка на подписку');
    }
    final headers = {'User-Agent': userAgent, 'Accept': '*/*', ...?device?.headers};

    final client = http.Client();
    late http.Response response;
    var current = uri;
    try {
      for (var hop = 0; ; hop++) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(headers);
        try {
          response = await http.Response.fromStream(await client.send(request).timeout(_timeout)).timeout(_timeout);
        } on Object catch (e) {
          throw SubscriptionException('Не удалось загрузить подписку: $e');
        }
        final location = response.headers['location'];
        if (!const {301, 302, 303, 307, 308}.contains(response.statusCode) || location == null) break;

        final Uri next;
        try {
          next = current.resolve(location.trim());
        } on FormatException {
          throw SubscriptionException('Панель переадресовала на неверный адрес');
        }
        if (next.scheme != 'http' && next.scheme != 'https') {
          // straight into an app: happ://crypt…, incy://… or happ://add/…
          return await _fetchWrapped(location.trim(), unwraps);
        }
        if (hop >= _maxRedirects) throw SubscriptionException('Слишком много переадресаций');
        current = next;
      }
    } finally {
      client.close();
    }

    if (response.statusCode != 200) {
      throw SubscriptionException('Панель ответила ${response.statusCode}');
    }
    // some panels put a byte order mark in front of the JSON
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).replaceFirst('\uFEFF', '');

    final type = response.headers['content-type']?.toLowerCase() ?? '';
    final page = type.contains('html') || body.trimLeft().startsWith('<');
    if (page) {
      final inner = WrappedLink.findIn(body);
      if (inner != null) return _fetchWrapped(inner, unwraps);
      throw SubscriptionException('По ссылке открылась веб-страница, а не подписка');
    }

    final List<Server> servers;
    try {
      servers = await parseBody(body);
    } on SubscriptionException {
      // a page served as plain text
      final inner = WrappedLink.findIn(body);
      if (inner == null) rethrow;
      return _fetchWrapped(inner, unwraps);
    }
    return (
      servers: servers,
      info: SubscriptionInfo.fromHeaders(response.headers),
      fallbackName: _nameFromDisposition(response.headers['content-disposition']) ?? current.host,
      // plain HTTP redirects are followed again on every refresh; only wrapped links are replaced
      url: url.trim(),
    );
  }

  Future<({List<Server> servers, SubscriptionInfo info, String fallbackName, String url})> _fetchWrapped(
    String link,
    int unwraps,
  ) async {
    if (unwraps >= _maxUnwraps) throw SubscriptionException('Слишком много вложенных ссылок');
    final inner = await WrappedLink.unwrap(link);
    if (inner == null) throw SubscriptionException('Панель переадресовала на неизвестную ссылку');
    return fetch(inner.url, unwraps: unwraps + 1);
  }

  static String? _nameFromDisposition(String? header) {
    if (header == null) return null;
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''', caseSensitive: false).firstMatch(header);
    if (m == null) return null;
    final name = Uri.decodeComponent(m.group(1)!).replaceAll(RegExp(r'\.(txt|json|yaml)$'), '').trim();
    return name.isEmpty ? null : name;
  }
}
