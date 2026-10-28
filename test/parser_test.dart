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

    group('subscription routing', () {
      // as Remnawave sends it, the proxy under its own tag
      final parsed = parseXrayJson(
        jsonEncode([
          {
            'remarks': 'NL',
            'outbounds': [
              _vless('nl-1'),
              {'tag': 'direct', 'protocol': 'freedom'},
              {'tag': 'block', 'protocol': 'blackhole'},
            ],
            'routing': {
              'domainStrategy': 'IPIfNonMatch',
              'rules': [
                {
                  'domain': ['geosite:category-ads-all'],
                  'outboundTag': 'block',
                },
                {
                  'domain': ['geosite:category-ru', 'domain:example.ru'],
                  'outboundTag': 'direct',
                },
                {
                  'ip': ['geoip:ru', 'geoip:private'],
                  'outboundTag': 'direct',
                },
                {
                  'domain': ['geosite:no-such-list'],
                  'outboundTag': 'direct',
                },
                {
                  'domain': ['geosite:youtube', 'ext:custom.dat:x'],
                  'outboundTag': 'nl-1',
                },
              ],
            },
            'dns': {
              'servers': [
                'https://1.1.1.1/dns-query',
                {
                  'address': '77.88.8.8',
                  'domains': ['geosite:category-ru'],
                },
                {
                  'address': '9.9.9.9',
                  'domains': ['geosite:no-such-list'],
                },
              ],
              'hosts': {'geosite:no-such-list': '127.0.0.1', 'example.com': '1.2.3.4'},
            },
          },
        ]),
      )!.single;
      const geo = GeoCodes(site: {'category-ads-all', 'category-ru', 'youtube'}, ip: {'ru', 'private'});

      test('the panel routing and DNS are kept, rules aimed at the old proxy tag follow it', () {
        expect(parsed.routing!['domainStrategy'], 'IPIfNonMatch');
        expect(((parsed.routing!['rules'] as List).last as Map)['outboundTag'], 'proxy');
        final back = Server.fromJson(jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>);
        expect(back.routing, parsed.routing);
        expect(back.dns, parsed.dns);
      });

      test('on: the panel rules after Orbit\'s DNS and LAN rules, missing lists left out', () {
        final notes = <String>[];
        final c = buildXrayConfig(
          server: parsed,
          settings: const OrbitSettings(),
          logPath: '/x/xray.log',
          ruCidrs: const ['5.3.0.0/16'],
          geo: geo,
          notes: notes,
        );
        final routing = c['routing'] as Map;
        expect(routing['domainStrategy'], 'IPIfNonMatch');
        final rules = (routing['rules'] as List).cast<Map>();
        expect(rules.map((r) => r['outboundTag']), ['orbit-dns', 'orbit-direct', 'block', 'direct', 'direct', 'proxy']);
        // no Orbit RU rules
        expect(rules.any((r) => (r['ip'] as List?)?.contains('5.3.0.0/16') ?? false), isFalse);
        expect(rules.last['domain'], ['geosite:youtube']);
        final dns = c['dns'] as Map;
        expect((dns['servers'] as List).length, 2);
        expect(dns['hosts'], {'example.com': '1.2.3.4'});
        expect(notes.last, contains('geosite:no-such-list'));
        expect(notes.last, contains('ext:custom.dat:x'));
      });

      test('off: Orbit routes by itself', () {
        final c = buildXrayConfig(
          server: parsed,
          settings: const OrbitSettings(subscriptionRouting: false),
          logPath: '/x/xray.log',
          ruCidrs: const ['5.3.0.0/16'],
          geo: geo,
        );
        final rules = ((c['routing'] as Map)['rules'] as List).cast<Map>();
        expect(rules.any((r) => (r['ip'] as List?)?.contains('5.3.0.0/16') ?? false), isTrue);
        expect((c['dns'] as Map)['servers'], ['https://1.1.1.1/dns-query']);
      });
    });

    test('fragment settings: checked when read back', () {
      expect(Fragment.validRange('100-200'), isTrue);
      expect(Fragment.validRange('200-100'), isFalse);
      expect(Fragment.validPackets('tlshello'), isTrue);
      expect(Fragment.validPackets('1-3'), isTrue);
      expect(Fragment.validPackets('abc'), isFalse);
      final f = Fragment.fromJson({'packets': '1-3', 'length': 'x', 'interval': '5'});
      expect(f, const Fragment(packets: '1-3', length: '100-200', interval: '5'));
    });

    test('fragment: the proxy dials through it', () {
      final outbounds = serverOutbounds(server, fragment: const Fragment(packets: '1-3', length: '50-80', interval: '5'));
      expect(outbounds.last['tag'], 'orbit-fragment');
      expect((outbounds.last['settings'] as Map)['fragment'], {'packets': '1-3', 'length': '50-80', 'interval': '5'});
      expect(((outbounds.first['streamSettings'] as Map)['sockopt'] as Map)['dialerProxy'], 'orbit-fragment');
      // the server's own copy is untouched
      expect((server.proxy['streamSettings'] as Map).containsKey('sockopt'), isFalse);
    });
  });
}
