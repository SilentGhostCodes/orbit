import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// INCY's `incy://crypt1/…` subscription links. INCY publishes the format, the key and a decoder
/// (MIT, github.com/INCY-DEV/incy-link-encoder) so other clients can open them; by their own account
/// it hides links from scanners rather than from people.
///
/// `incy://crypt1/` + base64url(iv[12] ‖ AES-256-GCM ciphertext ‖ tag[16]), the plaintext JSON like
/// `{"n":"Name","url":"https://…","v":1}`.
abstract class IncyLink {
  static const _prefix = 'incy://crypt1/';

  /// K1, as their encoder derives it from its key material (SHA-256 of the key:
  /// b6bf708471cc90043232967660aade86a50b4e57929db2e53c5fa34db624c08c).
  static const _keyHex = 'f6d40ea0c8a8899d7c682d09ba0d4165dfe2b3dd45e6bb3e25cb233cf00c2462';

  static bool matches(String text) => text.trim().toLowerCase().startsWith(_prefix);

  /// The subscription URL and the provider's name for it; null if [link] is not one or does not open.
  static ({String url, String? name})? decrypt(String link) {
    final text = link.trim();
    if (!matches(text)) return null;
    try {
      var payload = text.substring(_prefix.length).replaceAll(RegExp(r'/+$'), '');
      payload = base64Url.normalize(payload);
      final wire = base64Url.decode(payload);
      if (wire.length < 12 + 16 + 1) return null;
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(_key), 128, Uint8List.sublistView(wire, 0, 12), Uint8List(0)));
      final plain = cipher.process(Uint8List.sublistView(wire, 12));
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map) return null;
      final url = json['url'];
      if (url is! String || url.isEmpty) return null;
      final name = json['n'];
      return (url: url, name: name is String && name.trim().isNotEmpty ? name.trim() : null);
    } on Object {
      return null;
    }
  }

  static final Uint8List _key = Uint8List.fromList([
    for (var i = 0; i < _keyHex.length; i += 2) int.parse(_keyHex.substring(i, i + 2), radix: 16),
  ]);
}
