import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/core/xray_config.dart';
import 'package:orbit/data/qwdtt.dart';
import 'package:orbit/data/settings.dart';

void main() {
  const hashA = '8UkewARpV0aJoWheFZlR942el6unTZvhneulo-eU8gA';
  const hashB = 'Zm9vYmFyYmF6cXV4MTIzNDU2';

  test('qwdtt:// links', () {
    final r = Qwdtt.parse(
      'qwdtt://config?name=${Uri.encodeComponent('Дом')}&peer=1.2.3.4:56000&hashes=$hashA,$hashB&workers=18&port=9100&pass=secret',
    )!;
    final p = r.profiles.single;
    expect(p.name, 'Дом');
    expect(p.peer, '1.2.3.4:56000');
    expect(p.hashes, [hashA, hashB]);
    expect(p.password, 'secret');
    expect(p.workers, 18);
    expect(p.port, 9100);
  });

  test('wdtt:// links (the original app)', () {
    final p = Qwdtt.parse('wdtt://203.0.113.10:56000:56001:9000:MySecretPass16:$hashA')!.profiles.single;
    expect(p.peer, '203.0.113.10:56000');
    expect(p.hashes, [hashA]);
    expect(p.password, 'MySecretPass16');
    expect(p.port, 9000);
    expect(p.workers, QwdttProfile.defaultWorkers);
  });

  test('a profile as JSON, plain and base64; call links as hashes', () {
    final json = jsonEncode({
      'name': 'Работа',
      'server': '5.6.7.8',
      'dtlsPort': 56000,
      'hashes': ['https://vk.com/call/join/$hashA', hashA, 'bad hash!'],
      'password': 'pw',
    });
    for (final text in [json, base64.encode(utf8.encode(json))]) {
      final p = Qwdtt.parse(text)!.profiles.single;
      expect(p.name, 'Работа');
      expect(p.peer, '5.6.7.8:56000');
      expect(p.hashes, [hashA]); // the link's hash, once; the broken one left out
    }
  });

  test('a subscription: its name and every profile', () {
    final body = jsonEncode({
      'subscriptionName': 'Белые списки',
      'profiles': [
        {'name': 'A', 'peer': '1.1.1.1:56000', 'hashes': hashA, 'pass': 'x'},
        {'peer': '2.2.2.2:56000', 'hashes': [hashB], 'password': 'y', 'workers': 500},
      ],
    });
    final r = Qwdtt.parse(body)!;
    expect(r.name, 'Белые списки');
    expect(r.profiles.map((p) => p.name), ['A', 'qWDTT 2']);
    expect(r.profiles.last.workers, QwdttProfile.maxWorkers);
  });

  test('broken profiles say what is missing; other text is not qWDTT', () {
    expect(() => Qwdtt.parse('qwdtt://config?peer=1.2.3.4:56000&pass=x'), throwsA(isA<QwdttException>()));
    expect(() => Qwdtt.parse('qwdtt://config?peer=1.2.3.4:56000&hashes=$hashA'), throwsA(isA<QwdttException>()));
    expect(() => Qwdtt.parse('wdtt://1.2.3.4:56000'), throwsA(isA<QwdttException>()));
    expect(Qwdtt.parse('vless://abc@example.com:443'), isNull);
    expect(Qwdtt.parse('{"outbounds":[]}'), isNull);
    expect(Qwdtt.matches('qwdtt://config?x=1'), isTrue);
    expect(Qwdtt.matches('https://sub.example.com'), isFalse);
  });

  test('as a server: listed as qWDTT, its profile goes to the VPN service', () {
    final p = Qwdtt.parse('wdtt://203.0.113.10:56000:56001:9000:pw:$hashA')!.profiles.single;
    final server = p.toServer();
    expect(server.isQwdtt, isTrue);
    expect(server.protocol, 'qWDTT');
    expect(server.endpoint, isNull);
    expect(QwdttProfile.of(server)!.peer, '203.0.113.10:56000');

    const settings = OrbitSettings(fragment: true);
    // no fragment hop in front of the placeholder
    expect(serverOutbounds(server, fragment: settings.fragmentOptions), server.outbounds);
    final options = vpnOptions(settings, serverName: server.name, qwdtt: p, deviceId: 'abc123');
    expect(options['qwdtt'], containsPair('deviceId', 'abc123'));
    expect(options['qwdtt'], containsPair('dns', 'yandex'));
    expect(options['qwdtt'], containsPair('peer', '203.0.113.10:56000'));
    expect(vpnOptions(settings, serverName: 'x').containsKey('qwdtt'), isFalse);
  });
}
