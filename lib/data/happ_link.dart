import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pointycastle/export.dart';

/// Why a `happ://crypt…/` link did not open; the message is shown to the user as is.
class HappLinkException implements Exception {
  const HappLinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Happ's `happ://crypt…/` subscription links: `crypt` to `crypt4` are RSA (PKCS#1 v1.5) blocks
/// over base64, `crypt5` an RSA-wrapped ChaCha20-Poly1305 key picked by an 8-letter marker.
/// A port of github.com/LeeeeT/happ-decryptor; the keys live in [asset], built from that repo by
/// `tool/happ_keys.py`.
abstract class HappLink {
  static const asset = 'assets/happ/keys.json';

  /// Inputs past these are refused before any RSA runs.
  static const _maxLength = 16384;
  static const _maxBlocks = 32;

  static final _link = RegExp(r'^happ://(crypt[2-5]?)/([A-Za-z0-9+/=_\-]+)$', caseSensitive: false);

  static bool matches(String text) => text.trim().toLowerCase().startsWith('happ://crypt');

  static Future<String>? _keys;

  /// The subscription URL inside [link]. RSA runs on a background isolate, so the UI stays smooth.
  /// Throws [HappLinkException].
  static Future<String> decrypt(String link) async {
    final text = link.trim();
    if (!matches(text)) throw const HappLinkException('Это не ссылка happ://');
    final String keys;
    try {
      keys = await (_keys ??= rootBundle.loadString(asset));
    } on Object {
      _keys = null; // let the next attempt load it again
      throw const HappLinkException('Не удалось загрузить ключи Happ');
    }
    try {
      return await Isolate.run(_job(text, keys));
    } on HappLinkException {
      rethrow;
    } on Object {
      throw const HappLinkException('Не удалось открыть ссылку happ://');
    }
  }

  // Built outside [decrypt] so the closure sent to the isolate holds only the two strings.
  static String Function() _job(String link, String keys) => () => decryptWith(link, keys);

  /// Synchronous core of [decrypt], with the key file's JSON passed in (tests read it from disk).
  static String decryptWith(String link, String keysJson) {
    final text = link.trim();
    if (text.length > _maxLength) throw const HappLinkException('Ссылка happ:// слишком длинная');
    final m = _link.firstMatch(text);
    if (m == null) throw const HappLinkException('Ссылка happ:// повреждена или обрезана');
    final scheme = m.group(1)!.toLowerCase();
    final payload = m.group(2)!;

    final Map<String, dynamic> keys;
    try {
      keys = jsonDecode(keysJson) as Map<String, dynamic>;
    } on Object {
      throw const HappLinkException('Не удалось загрузить ключи Happ');
    }

    return scheme == 'crypt5' ? _crypt5(payload, keys) : _legacy(scheme, payload, keys);
  }

  // --- crypt … crypt4 ---------------------------------------------------------------------------

  static String _legacy(String scheme, String payload, Map<String, dynamic> keys) {
    final key = _key((keys['legacy'] as Map<String, dynamic>?)?[scheme]);
    if (key == null) throw const HappLinkException('Не удалось загрузить ключи Happ');
    final block = (key.modulus!.bitLength + 7) ~/ 8;
    final data = _b64(payload);
    if (data.isEmpty || data.length % block != 0) {
      throw const HappLinkException('Ссылка happ:// повреждена или обрезана');
    }
    if (data.length ~/ block > _maxBlocks) throw const HappLinkException('Ссылка happ:// слишком длинная');

    final out = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i += block) {
      out.add(_rsa(key, Uint8List.sublistView(data, i, i + block)));
    }
    return _text(out.takeBytes());
  }

  // --- crypt5 -----------------------------------------------------------------------------------

  static String _crypt5(String payload, Map<String, dynamic> keys) {
    final shuffled = _swapBlockHalves(Uint8List.fromList(ascii.encode(payload)));
    if (shuffled.length < 8) throw const HappLinkException('Ссылка happ:// повреждена или обрезана');

    final marker = ascii.decode([...shuffled.sublist(0, 4), ...shuffled.sublist(shuffled.length - 4)]);
    final key = _key((keys['crypt5'] as Map<String, dynamic>?)?[marker]);
    if (key == null) {
      throw const HappLinkException('Эта ссылка Happ зашифрована новым ключом — Orbit его пока не знает');
    }

    final body = Uint8List.sublistView(shuffled, 4, shuffled.length - 4);
    final preferSalted = body.length > 12 && !_isDigit(body[12]);
    HappLinkException? first;
    for (final salted in [preferSalted, !preferSalted]) {
      try {
        return _crypt5Body(body, key, salted);
      } on HappLinkException catch (e) {
        first ??= e;
      }
    }
    throw first!;
  }

  static String _crypt5Body(Uint8List body, RSAPrivateKey key, bool salted) {
    const broken = HappLinkException('Ссылка happ:// повреждена или обрезана');
    if (body.length < 13) throw broken;

    final nonce = Uint8List.sublistView(body, 0, 12);
    Uint8List? salt;
    var lengthStart = 12;
    if (salted) {
      if (body.length < 22) throw broken;
      salt = Uint8List.sublistView(body, 14, 22);
      lengthStart = 22;
    }

    var lengthEnd = lengthStart;
    while (lengthEnd < body.length && _isDigit(body[lengthEnd]) && lengthEnd - lengthStart < 9) {
      lengthEnd++;
    }
    if (lengthEnd == lengthStart) throw broken;
    final segment = int.parse(ascii.decode(body.sublist(lengthStart, lengthEnd)));
    final packed = Uint8List.sublistView(body, lengthEnd);
    if (packed.isEmpty || segment > packed.length - 1) throw broken;

    final encryptedUrl = latin1.decode(Uint8List.sublistView(packed, 1, segment + 1));
    final rsaCipher = _b64(latin1.decode(Uint8List.sublistView(packed, segment + 1)));
    if (rsaCipher.length != (key.modulus!.bitLength + 7) ~/ 8) throw broken;

    final chachaKey = _b64(latin1.decode(_swapAdjacent(_rsa(key, rsaCipher))));
    if (chachaKey.length != 32) throw broken;
    if (salt != null) {
      for (var i = 0; i < chachaKey.length; i++) {
        chachaKey[i] ^= salt[i % salt.length];
      }
    }

    final sealed = _b64(encryptedUrl);
    if (sealed.length < 16) throw broken;
    final Uint8List opened;
    try {
      final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
        ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(chachaKey), Uint8List.fromList(nonce)));
      final out = Uint8List(cipher.getOutputSize(sealed.length));
      var len = cipher.processBytes(sealed, 0, sealed.length, out, 0);
      len += cipher.doFinal(out, len); // checks the Poly1305 tag
      opened = Uint8List.sublistView(out, 0, len);
    } on Object {
      throw broken;
    }
    return _text(_b64(latin1.decode(_swapAdjacent(opened))));
  }

  // --- helpers ----------------------------------------------------------------------------------

  static RSAPrivateKey? _key(Object? json) {
    if (json is! Map) return null;
    final map = json;
    BigInt? big(String name) {
      final v = map[name];
      return v is String ? BigInt.tryParse(v, radix: 16) : null;
    }

    final n = big('n'), d = big('d'), p = big('p'), q = big('q');
    if (n == null || d == null || p == null || q == null) return null;
    try {
      return RSAPrivateKey(n, d, p, q);
    } on Object {
      return null;
    }
  }

  static Uint8List _rsa(RSAPrivateKey key, Uint8List block) {
    try {
      final cipher = PKCS1Encoding(RSAEngine())..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
      return cipher.process(block);
    } on Object {
      throw const HappLinkException('Ссылка happ:// повреждена или обрезана');
    }
  }

  /// Standard or URL-safe base64, with or without padding.
  static Uint8List _b64(String value) {
    var clean = value.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    clean = clean.replaceAll(RegExp(r'=+$'), '');
    clean = clean.padRight(clean.length + (4 - clean.length % 4) % 4, '=');
    try {
      return base64.decode(clean);
    } on FormatException {
      throw const HappLinkException('Ссылка happ:// повреждена или обрезана');
    }
  }

  static String _text(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const HappLinkException('Ссылка happ:// повреждена или обрезана');
    }
    if (text.trim().isEmpty) throw const HappLinkException('Ссылка happ:// пустая');
    return text.trim();
  }

  static bool _isDigit(int b) => b >= 0x30 && b <= 0x39;

  /// ABCD → BADC.
  static Uint8List _swapAdjacent(Uint8List data) {
    final out = Uint8List.fromList(data);
    for (var i = 0; i + 1 < out.length; i += 2) {
      out[i] = data[i + 1];
      out[i + 1] = data[i];
    }
    return out;
  }

  /// ABCD → CDAB for every whole 4-byte block; its own inverse.
  static Uint8List _swapBlockHalves(Uint8List data) {
    final out = Uint8List.fromList(data);
    final full = out.length - out.length % 4;
    for (var i = 0; i < full; i += 4) {
      out[i] = data[i + 2];
      out[i + 1] = data[i + 3];
      out[i + 2] = data[i];
      out[i + 3] = data[i + 1];
    }
    return out;
  }
}
