import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:orbit/core/libxray.dart';
import 'package:orbit/data/device.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/panel_client.dart';
import 'package:orbit/data/subscription_parser.dart';
import 'package:orbit/data/wrapped_link.dart';
import 'package:path_provider/path_provider.dart';

class SubscriptionException implements Exception {
  SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The panel answered, but not with servers: worth asking again as another app.
class _NoServers extends SubscriptionException {
  _NoServers(super.message);
}

typedef FetchResult = ({List<Server> servers, SubscriptionInfo info, String fallbackName, String url, PanelClient client});

/// Downloads, parses and stores subscriptions.
class SubscriptionRepo {
  SubscriptionRepo(this.userAgent, {this.device, http.Client Function()? httpClient})
    : _httpClient = httpClient ?? http.Client.new;

  /// Starts with "Orbit/" so a panel rule (Remnawave: `^(?:…|orbit)` → XRAY_JSON) can pick the format.
  final String userAgent;

  /// Sent as Remnawave's device headers (HWID), the same whichever app Orbit introduces itself as.
  final DeviceInfo? device;

  final http.Client Function() _httpClient;

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

  /// Downloads [url], introducing Orbit as [client] first (the one that worked last time) and, if
  /// the panel answers without servers, as the other [PanelClient]s in turn. Redirect pages are
  /// followed through: an HTTP redirect to `happ://…`, or a web page that opens Happ with an
  /// encrypted link, lead to the subscription inside. `url` in the result is the one to store and
  /// refresh: [url] itself, or the subscription a wrapped link held; `client`, the app that worked.
  Future<FetchResult> fetch(String url, {PanelClient client = PanelClient.orbit, int unwraps = 0}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw SubscriptionException('Это не ссылка на подписку');
    }
    final order = [client, for (final c in [PanelClient.orbit, ...PanelClient.fallbacks]) if (c != client) c];
    _NoServers? first;
    for (final c in order) {
      try {
        return await _fetchAs(url.trim(), uri, c, unwraps);
      } on _NoServers catch (e) {
        first ??= e; // Orbit's own answer explains it best
      }
    }
    throw SubscriptionException(first!.message);
  }

  Future<FetchResult> _fetchAs(String url, Uri uri, PanelClient client, int unwraps) async {
    final headers = {...client.headers(userAgent), 'Accept': '*/*', ...?device?.headers};

    final connection = _httpClient();
    late http.Response response;
    var current = uri;
    try {
      for (var hop = 0; ; hop++) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(headers);
        try {
          response = await http.Response.fromStream(await connection.send(request).timeout(_timeout)).timeout(_timeout);
        } on Object catch (e) {
          // unreachable is unreachable as any app: no point asking again
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
      connection.close();
    }

    if (response.statusCode != 200) {
      throw _NoServers('Панель ответила ${response.statusCode}');
    }
    // some panels put a byte order mark in front of the JSON
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).replaceFirst('\uFEFF', '');

    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (type.contains('html') || body.trimLeft().startsWith('<')) {
      final inner = WrappedLink.findIn(body);
      if (inner != null) return _fetchWrapped(inner, unwraps);
      throw _NoServers('По ссылке открылась веб-страница, а не подписка');
    }
    if (_isAccountInfo(body)) throw _NoServers('Панель не отдаёт серверы этому приложению');

    final List<Server> servers;
    try {
      servers = await parseBody(body);
    } on SubscriptionException catch (e) {
      // a page served as plain text
      final inner = WrappedLink.findIn(body);
      if (inner == null) throw _NoServers(e.message);
      return _fetchWrapped(inner, unwraps);
    }
    if (servers.isEmpty) throw _NoServers('В подписке не нашлось серверов');
    return (
      servers: servers,
      info: SubscriptionInfo.fromHeaders(response.headers),
      fallbackName: _nameFromDisposition(response.headers['content-disposition']) ?? current.host,
      // plain HTTP redirects are followed again on every refresh; only wrapped links are replaced
      url: url,
      client: client,
    );
  }

  /// Remnawave's answer to an app it has no format for: the subscription page's data, no servers.
  static bool _isAccountInfo(String body) {
    final t = body.trimLeft();
    if (!t.startsWith('{') || !t.contains('"isFound"')) return false;
    try {
      final json = jsonDecode(t);
      return json is Map && json.containsKey('isFound') && !json.containsKey('outbounds');
    } on FormatException {
      return false;
    }
  }

  Future<FetchResult> _fetchWrapped(String link, int unwraps) async {
    if (unwraps >= _maxUnwraps) throw SubscriptionException('Слишком много вложенных ссылок');
    final inner = await WrappedLink.unwrap(link);
    if (inner == null) throw SubscriptionException('Панель переадресовала на неизвестную ссылку');
    // a subscription Happ or INCY hands out (also from a redirect page) goes to that app first
    final client = WrappedLink.clientFor(link);
    return fetch(inner.url, client: client, unwraps: unwraps + 1);
  }

  static String? _nameFromDisposition(String? header) {
    if (header == null) return null;
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''', caseSensitive: false).firstMatch(header);
    if (m == null) return null;
    final name = Uri.decodeComponent(m.group(1)!).replaceAll(RegExp(r'\.(txt|json|yaml)$'), '').trim();
    return name.isEmpty ? null : name;
  }
}
