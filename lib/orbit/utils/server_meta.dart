/// Turns outbound tags like "🇳🇱 Amsterdam | Reality" into what the server list shows.
library;

final _flagPattern = RegExp('[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);
// Hiddify marks hidden or decorated tags with "§…"
final _hiddifySuffix = RegExp('§[^]*');

/// Country code (ISO 3166-1 alpha-2, upper case) to its flag emoji.
String flagEmoji(String countryCode) {
  final cc = countryCode.toUpperCase();
  if (cc.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(cc)) return '';
  return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

String? _countryFromFlag(String text) {
  final match = _flagPattern.firstMatch(text);
  if (match == null) return null;
  final runes = match.group(0)!.runes.toList();
  return String.fromCharCodes(runes.map((r) => r - 0x1F1E6 + 0x41));
}

const _keywords = <String, String>{
  'amsterdam': 'NL', 'амстердам': 'NL', 'netherlands': 'NL', 'нидерланд': 'NL', 'holland': 'NL',
  'helsinki': 'FI', 'хельсинки': 'FI', 'finland': 'FI', 'финлянд': 'FI',
  'frankfurt': 'DE', 'франкфурт': 'DE', 'germany': 'DE', 'герман': 'DE', 'berlin': 'DE', 'берлин': 'DE',
  'stockholm': 'SE', 'стокгольм': 'SE', 'sweden': 'SE', 'швец': 'SE',
  'new york': 'US', 'нью-йорк': 'US', 'нью йорк': 'US', 'usa': 'US', 'сша': 'US', 'united states': 'US',
  'los angeles': 'US', 'лос-анджелес': 'US', 'miami': 'US', 'chicago': 'US',
  'istanbul': 'TR', 'стамбул': 'TR', 'turkey': 'TR', 'турц': 'TR', 'türkiye': 'TR',
  'london': 'GB', 'лондон': 'GB', 'united kingdom': 'GB', 'великобритан': 'GB', 'england': 'GB',
  'paris': 'FR', 'париж': 'FR', 'france': 'FR', 'франц': 'FR',
  'warsaw': 'PL', 'варшав': 'PL', 'poland': 'PL', 'польш': 'PL',
  'riga': 'LV', 'рига': 'LV', 'latvia': 'LV', 'латви': 'LV',
  'tallinn': 'EE', 'таллин': 'EE', 'estonia': 'EE', 'эстон': 'EE',
  'vilnius': 'LT', 'вильнюс': 'LT', 'lithuania': 'LT', 'литв': 'LT',
  'moscow': 'RU', 'москва': 'RU', 'russia': 'RU', 'росси': 'RU', 'saint petersburg': 'RU', 'петербург': 'RU',
  'almaty': 'KZ', 'алматы': 'KZ', 'kazakhstan': 'KZ', 'казахстан': 'KZ',
  'tokyo': 'JP', 'токио': 'JP', 'japan': 'JP', 'япони': 'JP',
  'singapore': 'SG', 'сингапур': 'SG',
  'hong kong': 'HK', 'гонконг': 'HK',
  'zurich': 'CH', 'цюрих': 'CH', 'switzerland': 'CH', 'швейцар': 'CH',
  'vienna': 'AT', 'вена': 'AT', 'austria': 'AT', 'австри': 'AT',
  'prague': 'CZ', 'прага': 'CZ', 'czech': 'CZ', 'чехи': 'CZ',
  'milan': 'IT', 'милан': 'IT', 'italy': 'IT', 'итали': 'IT',
  'madrid': 'ES', 'мадрид': 'ES', 'spain': 'ES', 'испани': 'ES',
  'oslo': 'NO', 'осло': 'NO', 'norway': 'NO', 'норвеги': 'NO',
  'copenhagen': 'DK', 'копенгаген': 'DK', 'denmark': 'DK', 'дани': 'DK',
  'toronto': 'CA', 'торонто': 'CA', 'canada': 'CA', 'канад': 'CA',
  'dubai': 'AE', 'дубай': 'AE', 'uae': 'AE', 'оаэ': 'AE',
  'tbilisi': 'GE', 'тбилиси': 'GE', 'georgia': 'GE', 'грузи': 'GE',
  'yerevan': 'AM', 'ереван': 'AM', 'armenia': 'AM', 'армени': 'AM',
  'bucharest': 'RO', 'бухарест': 'RO', 'romania': 'RO', 'румыни': 'RO',
  'sofia': 'BG', 'софия': 'BG', 'bulgaria': 'BG', 'болгари': 'BG',
  'kyiv': 'UA', 'киев': 'UA', 'ukraine': 'UA', 'украин': 'UA',
  'serbia': 'RS', 'серби': 'RS', 'belgrade': 'RS', 'белград': 'RS',
  'moldova': 'MD', 'молдов': 'MD', 'chisinau': 'MD', 'кишин': 'MD',
};

/// The best guess at the server's country: a flag in its name, a known city or country in it, or the
/// country the core looked its IP up in.
String? guessCountry(String tag, {String? ipCountry}) {
  final fromFlag = _countryFromFlag(tag);
  if (fromFlag != null) return fromFlag;
  final lower = tag.toLowerCase();
  for (final entry in _keywords.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  if (ipCountry != null && ipCountry.length == 2) return ipCountry.toUpperCase();
  // a bare two-letter code at the start: "NL-1", "DE Frankfurt"
  final code = RegExp(r'^([A-Za-z]{2})(?:[\s\-_|·]|$)').firstMatch(tag.trim());
  return code?.group(1)?.toUpperCase();
}

/// The tag without its flag, Hiddify's "§" suffix and stray separators.
String displayName(String tag) {
  final name = tag
      .replaceFirst(_hiddifySuffix, '')
      .replaceAll(_flagPattern, '')
      .trim()
      .replaceFirst(RegExp(r'^[\s|·\-_]+'), '')
      .trim();
  return name.isEmpty ? tag : name;
}

/// "VLESS Reality", "Hysteria2", "Trojan" and the like, from the core's outbound type plus what the
/// config says about its transport.
String protocolLabel(String type, {String? transport, bool reality = false}) {
  final base = switch (type.toLowerCase()) {
    'vless' => 'VLESS',
    'vmess' => 'VMess',
    'trojan' => 'Trojan',
    'shadowsocks' || 'ss' => 'Shadowsocks',
    'hysteria2' || 'hy2' => 'Hysteria2',
    'hysteria' => 'Hysteria',
    'tuic' => 'TUIC',
    'wireguard' => 'WireGuard',
    'ssh' => 'SSH',
    'socks' => 'SOCKS',
    'http' => 'HTTP',
    'anytls' => 'AnyTLS',
    'urltest' => 'Авто',
    'selector' => 'Группа',
    '' => '',
    final other => other.toUpperCase(),
  };
  if (reality) return '$base Reality';
  final t = transport?.toLowerCase();
  if (t == null || t.isEmpty || t == 'tcp') return base;
  final label = switch (t) {
    'xhttp' || 'splithttp' => 'XHTTP',
    'httpupgrade' => 'HTTPUpgrade',
    'ws' => 'WS',
    'grpc' => 'gRPC',
    'http' || 'h2' => 'H2',
    'quic' => 'QUIC',
    final other => other.toUpperCase(),
  };
  return '$base $label';
}
