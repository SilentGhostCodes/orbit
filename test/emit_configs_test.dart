// Writes the configs Orbit builds for a Remnawave-style server, for checking them against libXray.
// Run with ORBIT_EMIT_DIR=<dir>; skipped otherwise.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/core/xray_config.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/data/subscription_parser.dart';

void main() {
  final dir = Platform.environment['ORBIT_EMIT_DIR'];
  test('emit', () {
    final port = Platform.environment['ORBIT_SERVER_PORT'] ?? '443';
    final sub = jsonEncode([
      {
        'remarks': '🇩🇪 Франкфурт CDN',
        'dns': {
          'servers': ['geosite:category-ru'],
        },
        'routing': {
          'rules': [
            {'outboundTag': 'direct', 'ip': ['geoip:private']},
          ],
        },
        'inbounds': [
          {'port': 10808, 'protocol': 'socks'},
        ],
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': '127.0.0.1',
                  'port': int.parse(port),
                  'users': [
                    {'id': '11111111-2222-3333-4444-555555555555', 'encryption': 'none'},
                  ],
                },
              ],
            },
            'streamSettings': {
              'network': 'xhttp',
              'xhttpSettings': {
                'path': '/xh',
                'mode': 'packet-up',
                'extra': {
                  'xPaddingBytes': '100-1000',
                  'xmux': {'maxConcurrency': '4-8'},
                },
              },
            },
          },
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
      },
    ]);
    final servers = parseXrayJson(sub)!;
    expect(servers.single.protocol, 'VLESS XHTTP');
    expect(servers.single.proxy['tag'], 'proxy');
    if (dir == null) return;
    for (final fragment in [false, true]) {
      final settings = OrbitSettings(fragment: fragment);
      final full = buildXrayConfig(
        server: servers.single,
        settings: settings,
        logPath: '$dir/xray.log',
        ruCidrs: parseCidrList(File('assets/geo/ru4.txt').readAsStringSync()),
      );
      File('$dir/full${fragment ? '_fragment' : ''}.json').writeAsStringSync(jsonEncode(full));
      File('$dir/ping${fragment ? '_fragment' : ''}.json').writeAsStringSync(pingConfig(servers.single, fragment: fragment));
    }
  });
}
