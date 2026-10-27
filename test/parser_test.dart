import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/core/xray_config.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/data/subscription_parser.dart';
import 'package:orbit/util/format.dart';

Map<String, dynamic> _vless(String tag, {String network = 'xhttp', String security = 'tls'}) => {
  'tag': tag,
  'protocol': 'vless',
  'settings': {
    'vnext': [
      {
        'address': 'example.com',
        'port': 443,
        'users': [
          {'id': '11111111-2222-3333-4444-555555555555', 'encryption': 'none'},
        ],
      },
    ],
  },
  'streamSettings': {'network': network, 'security': security},
};

void main() {
  group('Xray JSON', () {
    test('a Remnawave list: one server per config, proxy first', () {
      final servers = parseXrayJson(
        jsonEncode([
          {
            'remarks': '🇩🇪 Франкфурт',
            'outbounds': [
              {'tag': 'direct', 'protocol': 'freedom'},
              _vless('proxy'),
            ],
          },
          {
            'remarks': '🇫🇮 Хельсинки',
            'outbounds': [_vless('proxy', network: 'raw', security: 'reality')],
          },
        ]),
      )!;
      expect(servers.map((s) => s.name), ['🇩🇪 Франкфурт', '🇫🇮 Хельсинки']);
      expect(servers.first.outbounds.map((o) => o['tag']), ['proxy', 'direct']);
      expect(servers.map((s) => s.protocol), ['VLESS XHTTP', 'VLESS Reality']);
      expect(servers.first.country, 'DE');
    });

    test('a fragment chain that dialled through the proxy keeps doing so', () {
      final servers = parseXrayJson(
        jsonEncode({
          'remarks': 'chain',
          'outbounds': [
            _vless('main'),
            {
              'tag': 'next',
              'protocol': 'freedom',
              'streamSettings': {
                'sockopt': {'dialerProxy': 'main'},
              },
            },
          ],
        }),
      )!;
      final next = servers.single.outbounds.last;
      expect((next['streamSettings'] as Map)['sockopt'], {'dialerProxy': 'proxy'});
    });

    test('a bare node list without remarks: every proxy is a server', () {
      final servers = parseXrayJson(
        jsonEncode({
          'outbounds': [_vless('A'), _vless('B'), {'tag': 'direct', 'protocol': 'freedom'}],
        }),
      )!;
      expect(servers.map((s) => s.name), ['A', 'B']);
    });

    test('anything else is not Xray JSON', () {
      expect(parseXrayJson('vless://x@y:1#z'), isNull);
      expect(parseXrayJson('{"outbounds":[{"type":"vless"}]}'), isNull);
    });

    test('names stay unique', () {
      final s = Server(name: 'X', outbounds: [_vless('proxy')]);
      expect(dedupeNames([s, s, s]).map((s) => s.name), ['X', 'X (2)', 'X (3)']);
    });
  });

  test('Xray JSON after a byte order mark', () {
    final servers = parseXrayJson('\uFEFF${jsonEncode([
      {'remarks': 'A', 'outbounds': [_vless('proxy')]},
    ])}');
    expect(servers?.single.name, 'A');
  });

  group('traffic line', () {
    Subscription sub({required int used, required int total}) =>
        Subscription(id: 'x', name: 'x', servers: const [], updatedAt: DateTime(2026), download: used, total: total);
    const gb = 1024 * 1024 * 1024;

    test('unlimited: what was used, of infinity, and an empty bar', () {
      final s = summarize(sub(used: 12 * gb, total: 0));
      expect(s.traffic, '12 ГБ из ∞');
      expect(s.ratio, 0);
      expect(summarize(sub(used: 350 * 1024 * 1024, total: 0)).traffic, '350 МБ из ∞');
    });

    test('limited: used of total, and the bar filled that far', () {
      final s = summarize(sub(used: 48 * gb, total: 100 * gb));
      expect(s.traffic, '48 из 100 ГБ');
      expect(s.ratio, closeTo(.48, .001));
      expect(summarize(sub(used: 0, total: 100 * gb)).traffic, '0 МБ из 100 ГБ');
    });
  });

  test('subscription headers', () {
    final info = SubscriptionInfo.fromHeaders({
      'Subscription-Userinfo': 'upload=1073741824; download=2147483648; total=10737418240; expire=1924992000',
      'profile-title': 'base64:${base64.encode(utf8.encode('Основная'))}',
      'profile-update-interval': '6',
    });
    expect(info.title, 'Основная');
    expect(info.upload + info.download, 3 * 1073741824);
    expect(info.total, 10737418240);
    expect(info.expire, DateTime.fromMillisecondsSinceEpoch(1924992000 * 1000));
    expect(info.updateHours, 6);
  });

  group('config', () {
    final server = Server(name: 'S', outbounds: [_vless('proxy'), {'tag': 'direct', 'protocol': 'freedom'}]);

    test('tun in, server first, own outbounds after it, RU bypass rules', () {
      final c = buildXrayConfig(
        server: server,
        settings: const OrbitSettings(),
        logPath: '/x/xray.log',
        ruCidrs: const ['5.3.0.0/16'],
      );
      final outbounds = (c['outbounds'] as List).map((o) => (o as Map)['tag']).toList();
      expect(outbounds, ['proxy', 'direct', 'orbit-direct', 'orbit-block', 'orbit-dns']);
      expect(((c['inbounds'] as List).single as Map)['protocol'], 'tun');
      final rules = ((c['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rules.first['outboundTag'], 'orbit-dns');
      expect(rules.any((r) => (r['ip'] as List?)?.contains('5.3.0.0/16') ?? false), isTrue);
      expect(rules.any((r) => (r['domain'] as List?)?.contains('domain:ru') ?? false), isTrue);
    });

    test('everything through the server: no RU rules', () {
      final c = buildXrayConfig(
        server: server,
        settings: const OrbitSettings(routing: RoutingMode.all),
        logPath: '/x/xray.log',
        ruCidrs: const ['5.3.0.0/16'],
      );
      final rules = ((c['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rules.length, 2);
    });

    test('fragment: the proxy dials through it', () {
      final outbounds = serverOutbounds(server, fragment: true);
      expect(outbounds.last['tag'], 'orbit-fragment');
      expect(((outbounds.first['streamSettings'] as Map)['sockopt'] as Map)['dialerProxy'], 'orbit-fragment');
      // the server's own copy is untouched
      expect((server.proxy['streamSettings'] as Map).containsKey('sockopt'), isFalse);
    });
  });
}
