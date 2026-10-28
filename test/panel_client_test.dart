import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbit/data/panel_client.dart';
import 'package:orbit/data/subscription_repo.dart';

const _url = 'https://panel.example.com/sub/abc';

// a Remnawave Xray JSON answer with one server
final _xrayJson = jsonEncode([
  {
    'remarks': '🇩🇪 Франкфурт',
    'outbounds': [
      {
        'tag': 'proxy',
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
        'streamSettings': {'network': 'raw', 'security': 'reality'},
      },
    ],
  },
]);

// what Remnawave sends an app it has no format for
const _accountInfo = '{"isFound":true,"user":{"shortUuid":"abc","daysLeft":4,"trafficLimit":"40.00 GiB"}}';

http.Response _json(String body, {Map<String, String> headers = const {}}) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

/// A panel that serves [answer] per User-Agent and records who asked.
({SubscriptionRepo repo, List<String> agents}) _panel(http.Response Function(String agent) answer) {
  final agents = <String>[];
  // a fresh client per request, as the repo closes each one
  MockClient client() => MockClient((request) async {
    final agent = request.headers['User-Agent'] ?? '';
    agents.add(agent);
    return answer(agent);
  });
  return (repo: SubscriptionRepo('Orbit/1.8.0 (android)', httpClient: client), agents: agents);
}

void main() {
  test('a panel that answers only INCY: asked again as INCY, which is remembered', () async {
    final p = _panel(
      (agent) => agent.startsWith('INCY/')
          ? _json(_xrayJson, headers: {'subscription-userinfo': 'upload=0; download=0; total=42949672960; expire=1793650015'})
          : _json(_accountInfo),
    );
    final r = await p.repo.fetch(_url);
    expect(r.client, PanelClient.incy);
    expect(r.servers.map((s) => s.name), ['🇩🇪 Франкфурт']);
    expect(r.info.total, 42949672960);
    expect(r.url, _url);
    expect(p.agents, ['Orbit/1.8.0 (android)', 'INCY/3.3.9/android Dalvik/2.1.0']);

    // the next refresh goes straight to INCY
    p.agents.clear();
    expect((await p.repo.fetch(_url, client: r.client)).client, PanelClient.incy);
    expect(p.agents, ['INCY/3.3.9/android Dalvik/2.1.0']);
  });

  test('a panel that knows Orbit is asked once', () async {
    final p = _panel((_) => _json(_xrayJson));
    expect((await p.repo.fetch(_url)).client, PanelClient.orbit);
    expect(p.agents, hasLength(1));
  });

  test('every app refused: the error Orbit got, after asking each once', () async {
    final p = _panel((_) => http.Response('not found', 404));
    await expectLater(
      p.repo.fetch(_url),
      throwsA(isA<SubscriptionException>().having((e) => e.message, 'message', 'Панель ответила 404')),
    );
    expect(p.agents, hasLength(3));
  });

  test('an unreachable panel is not asked again as other apps', () async {
    var calls = 0;
    final repo = SubscriptionRepo(
      'Orbit/1.8.0 (android)',
      httpClient: () => MockClient((_) async {
        calls++;
        throw http.ClientException('connection refused');
      }),
    );
    await expectLater(repo.fetch(_url), throwsA(isA<SubscriptionException>()));
    expect(calls, 1);
  });

  test('stored names map back, unknown ones fall back to Orbit', () {
    expect(PanelClient.fromName('incy'), PanelClient.incy);
    expect(PanelClient.fromName(null), PanelClient.orbit);
    expect(PanelClient.fromName('something'), PanelClient.orbit);
  });
}
