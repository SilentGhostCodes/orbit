import 'dart:convert';

import 'package:orbit/data/happ_link.dart';
import 'package:orbit/data/incy_link.dart';
import 'package:orbit/data/subscription_repo.dart';

/// Links that carry a subscription inside them (`happ://crypt…`, `incy://crypt1/…`,
/// `happ://add/<url>`), and web pages that carry such a link: providers hand out
/// `https://…/t/<token>` pages that open Happ with an encrypted link from a script, a button or a
/// redirect. [findIn] digs the link out of such a page, [unwrap] opens it.
abstract class WrappedLink {
  static final _add = RegExp(r'^happ://add/(.+)$', caseSensitive: false);

  // in a page: encrypted links first (they are what the page exists for), then happ://add/
  static final _encryptedInPage = RegExp(
    r'(?:happ://crypt[2-5]?|incy://crypt1)/[A-Za-z0-9+/=_\-]+',
    caseSensitive: false,
  );
  static final _addInPage = RegExp(r'''happ://add/[^\s"'<>\\`]+''', caseSensitive: false);
  static final _percentEncoded = RegExp(r'(?:happ|incy)%3A%2F%2F[A-Za-z0-9%._~+\-/=]+', caseSensitive: false);
  static final _atob = RegExp(r'''atob\(\s*["'`]([A-Za-z0-9+/=_\-]{8,})["'`]\s*\)''');

  /// Pages bigger than this are not searched (a redirect page is a few kilobytes).
  static const _maxPage = 2 * 1024 * 1024;

  static bool matches(String text) {
    final t = text.trim();
    return HappLink.matches(t) || IncyLink.matches(t) || _add.hasMatch(t);
  }

  /// What [link] carries: usually a subscription URL (plus a name, for INCY), but Happ can wrap
  /// share links too. Null if [link] is not one of these; throws [SubscriptionException] if it is
  /// one but does not open.
  static Future<({String url, String? name})?> unwrap(String link) async {
    final text = link.trim();
    if (IncyLink.matches(text)) {
      final r = IncyLink.decrypt(text);
      if (r == null) throw SubscriptionException('Не удалось открыть ссылку incy://');
      return (url: r.url.trim(), name: r.name);
    }
    if (HappLink.matches(text)) {
      try {
        return (url: (await HappLink.decrypt(text)).trim(), name: null);
      } on HappLinkException catch (e) {
        throw SubscriptionException(e.message);
      }
    }
    final add = _add.firstMatch(text);
    if (add != null) {
      var inner = add.group(1)!.trim();
      if (inner.toLowerCase().startsWith('http%3a')) {
        try {
          inner = Uri.decodeComponent(inner);
        } on Object {
          throw SubscriptionException('Ссылка happ://add/ повреждена');
        }
      }
      if (!inner.startsWith('http://') && !inner.startsWith('https://')) {
        throw SubscriptionException('Ссылка happ://add/ повреждена');
      }
      return (url: inner, name: null);
    }
    return null;
  }

  /// The first link [matches] accepts found in a web page, wherever the page keeps it: markup, a
  /// script string (with `\/` or `/` escapes), HTML entities, percent-encoding or `atob("…")`.
  static String? findIn(String page) {
    if (page.length > _maxPage) return null;
    final normal = _unescape(page);
    final found = _search(normal);
    if (found != null) return found;
    for (final m in _atob.allMatches(normal)) {
      final decoded = _base64Text(m.group(1)!);
      if (decoded == null) continue;
      final inner = _search(_unescape(decoded));
      if (inner != null) return inner;
    }
    return null;
  }

  static String? _search(String text) {
    final encrypted = _encryptedInPage.firstMatch(text);
    if (encrypted != null) return encrypted.group(0);
    for (final m in _percentEncoded.allMatches(text)) {
      try {
        final decoded = Uri.decodeComponent(m.group(0)!);
        final inner = _encryptedInPage.firstMatch(decoded) ?? _addInPage.firstMatch(decoded);
        if (inner != null) return inner.group(0);
      } on Object {
        continue; // a stray % that is not an escape, or not UTF-8
      }
    }
    return _addInPage.firstMatch(text)?.group(0);
  }

  static String _unescape(String s) => s
      .replaceAll(r'\/', '/')
      .replaceAllMapped(
        RegExp(r'\\u00([0-7][0-9a-fA-F])'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]{1,2});'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#([0-9]{1,3});'), (m) {
        final c = int.parse(m.group(1)!);
        return c < 128 ? String.fromCharCode(c) : m.group(0)!;
      })
      .replaceAll('&colon;', ':')
      .replaceAll('&sol;', '/')
      .replaceAll('&amp;', '&');

  static String? _base64Text(String value) {
    var clean = value.replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'=+$'), '');
    clean = clean.padRight(clean.length + (4 - clean.length % 4) % 4, '=');
    try {
      return utf8.decode(base64.decode(clean), allowMalformed: true);
    } on FormatException {
      return null;
    }
  }
}
