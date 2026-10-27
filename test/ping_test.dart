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

  test('pings go to libXray five at a time, and every server gets a result', () async {
    final batches = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('orbit/native'),
      (call) async {
        final request = jsonDecode((call.arguments as Map)['request'] as String) as Map<String, dynamic>;
        final configs = (request['payload'] as Map)['configs'] as List;
        batches.add(configs.length);
        // what libXray says past its limit
        if (configs.length > 5) {
          return jsonEncode({'success': false, 'error': 'ping batch contains more than 5 configs'});
        }
        return jsonEncode({
          'success': true,
          'data': {
            'results': [
              for (final c in configs) {'success': true, 'delay': jsonDecode(c['xrayJson'] as String)['outbounds'][0]['port']},
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
          Boot(version: '1', settings: const OrbitSettings(), subscriptions: [sub], ruCidrs: const [], logPath: '/x'),
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

  test('names and protocols as the list shows them', () {
    expect(displayNameOf('🇪🇺 Европа | Авто'), 'Европа · Авто');
    expect(protocolLabel('hysteria', transport: 'hysteria'), 'Hysteria2');
    expect(protocolLabel('vless', transport: 'grpc', reality: true), 'VLESS Reality');
  });
}
