import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/utils/xray_json.dart';

Map<String, dynamic> _config(String remarks, String network, {String security = 'tls'}) => {
  'remarks': remarks,
  'inbounds': [
    {'port': 10808, 'protocol': 'socks'},
  ],
  'outbounds': [
    {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': 'cdn.example.com',
            'port': 443,
            'users': [
              {'id': '11111111-2222-3333-4444-555555555555', 'encryption': 'none'},
            ],
          },
        ],
      },
      'streamSettings': {
        'network': network,
        'security': security,
        'xhttpSettings': {
          'path': '/xh',
          'mode': 'packet-up',
          'extra': {
            'xmux': {'maxConcurrency': '16-32'},
          },
        },
      },
    },
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
  'routing': {
    'rules': [
      {'outboundTag': 'direct', 'domain': ['geosite:category-ru']},
    ],
  },
};

void main() {
  test('leaves links and sing-box JSON alone', () {
    expect(xrayJsonToSingbox('vless://id@host:443?type=tcp#a'), isNull);
    expect(
      xrayJsonToSingbox(
        jsonEncode({
          'outbounds': [
            {'type': 'vless', 'tag': 'a'},
          ],
        }),
      ),
      isNull,
    );
  });

  test('wraps each Xray config, whole, in an xray outbound', () {
    final out = xrayJsonToSingbox(
      jsonEncode([
        _config('🇩🇪 Франкфурт CDN', 'xhttp'),
        _config('Хельсинки', 'raw', security: 'reality'),
        _config('Хельсинки', 'ws'),
      ]),
    )!;
    final outbounds = (jsonDecode(out) as Map)['outbounds'] as List;
    expect(outbounds, hasLength(3));
    expect(outbounds.map((o) => o['type']), everyElement('xray'));
    expect(outbounds.map((o) => o['tag']), ['🇩🇪 Франкфурт CDN', 'Хельсинки', 'Хельсинки 2']);
    // nothing is lost on the way: the core gets the panel's config as is
    expect(outbounds.first['xconfig'], _config('🇩🇪 Франкфурт CDN', 'xhttp'));

    final servers = parseServers(out);
    expect(servers.map((s) => s.protocol), ['VLESS XHTTP', 'VLESS Reality', 'VLESS WS']);
  });
}
