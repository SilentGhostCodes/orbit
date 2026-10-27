import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/util/server_meta.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pings go to libXray five at a time with the chosen settings, and every server gets a result', () async {
    final batches = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('orbit/native'),
      (call) async {
        expect(call.method, 'orbitPing');
        final request = jsonDecode((call.arguments as Map)['request'] as String) as Map<String, dynamic>;
        expect(
          [request['method'], request['mode'], request['timeout'], request['url']],
          ['HEAD', 'keepalive', 9, 'https://cp.cloudflare.com/'],
        );
        final configs = request['configs'] as List;
        batches.add(configs.length);
        // what libXray says past its limit
        if (configs.length > 5) {
          return jsonEncode({'success': false, 'error': 'ping batch contains more than 5 configs'});
        }
        return jsonEncode({
          'success': true,
          'data': {
            'results': [
              for (final c in configs)
                {'success': true, 'delay': jsonDecode(c['xrayJson'] as String)['outbounds'][0]['port']},
            ],
          },
        });
      },
    );

    final servers = [
      for (var i = 0; i < 12; i++)
        Server(
          name: 'S$i',
          outbounds: [
            {'tag': 'proxy', 'protocol': 'vless', 'port': 100 + i},
          ],
        ),
    ];
    final sub = Subscription(id: 'x', name: 'x', servers: servers, updatedAt: DateTime(2026));
    final container = ProviderContainer(
      overrides: [
        bootProvider.overrideWithValue(
          Boot(
            version: '1',
            settings: const OrbitSettings(
              pingType: PingType.proxyHead,
              pingMode: PingMode.keepAlive,
              pingTimeout: 9,
              pingUrl: 'https://cp.cloudflare.com/',
            ),
            subscriptions: [sub],
            ruCidrs: const [],
            logPath: '/x',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(pingsProvider.notifier).pingAll(sub);
    expect(batches, [5, 5, 2]);
    expect(result.length, 12);
    expect(result['S11'], 111);
    final pings = container.read(pingsProvider);
    expect(pings.error, isNull);
    expect(pings.running, isEmpty);
  });

  test('TCP and ICMP pings find the server address in each outbound shape', () {
    Server server(Map<String, dynamic> settings) => Server(
      name: 's',
      outbounds: [
        {'tag': 'proxy', 'protocol': 'x', 'settings': settings},
      ],
    );
    expect(
      server({
        'vnext': [
          {'address': 'a.example', 'port': 443},
        ],
      }).endpoint,
      (host: 'a.example', port: 443),
    );
    expect(
      server({
        'servers': [
          {'address': '1.2.3.4', 'port': '8443'},
        ],
      }).endpoint,
      (host: '1.2.3.4', port: 8443),
    );
    expect(server({'address': 'h.example', 'port': 3478}).endpoint, (host: 'h.example', port: 3478));
    expect(
      server({
        'peers': [
          {'endpoint': '[2001:db8::1]:51820'},
        ],
      }).endpoint,
      (host: '2001:db8::1', port: 51820),
    );
    expect(server({}).endpoint, isNull);
  });

  test('ping settings survive a save', () {
    const s = OrbitSettings(pingType: PingType.icmp, pingMode: PingMode.double, pingTimeout: 12, pingUrl: 'http://x/');
    final back = OrbitSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(
      [back.pingType, back.pingMode, back.pingTimeout, back.pingUrl],
      [PingType.icmp, PingMode.double, 12, 'http://x/'],
    );
    expect(OrbitSettings.fromJson(const {'pingTimeout': 40}).pingTimeout, 15);
  });

  test('names and protocols as the list shows them', () {
    expect(displayNameOf('🇪🇺 Европа | Авто'), 'Европа · Авто');
    expect(protocolLabel('hysteria', transport: 'hysteria'), 'Hysteria2');
    expect(protocolLabel('vless', transport: 'grpc', reality: true), 'VLESS Reality');
  });
}
