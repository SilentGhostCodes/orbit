import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbit/data/panel_client.dart';
import 'package:orbit/data/subscription_repo.dart';
import 'package:orbit/data/wrapped_link.dart';

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
  // HappLink reads its keys from the asset bundle
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a plain link is asked for strictly as Orbit', () async {
    final p = _panel((agent) => agent.startsWith('INCY/') ? _json(_xrayJson) : http.Response('not found', 404));
    await expectLater(
      p.repo.fetch(_url),
      throwsA(isA<SubscriptionException>().having((e) => e.message, 'message', 'Панель ответила 404')),
    );
    expect(p.agents, ['Orbit/1.8.0 (android)']);

    final ok = _panel((_) => _json(_xrayJson));
    final r = await ok.repo.fetch(_url);
    expect((r.client, r.retry), (PanelClient.orbit, false));
    expect(ok.agents, hasLength(1));
  });

  test('a plain link the panel says it does not know Orbit for (horu): INCY, kept for refreshes', () async {
    final p = _panel(
      (agent) => agent.startsWith('INCY/')
          ? _json(_xrayJson, headers: {'subscription-userinfo': 'upload=0; download=0; total=42949672960; expire=1793650015'})
          : _json(_accountInfo),
    );
    final r = await p.repo.fetch(_url);
    expect((r.client, r.retry), (PanelClient.incy, false));
    expect(r.info.total, 42949672960);
    expect(p.agents, ['Orbit/1.8.0 (android)', 'INCY/3.3.9/android Dalvik/2.1.0']);

    p.agents.clear();
    expect((await p.repo.fetch(_url, client: r.client, retry: r.retry)).client, PanelClient.incy);
    expect(p.agents, ['INCY/3.3.9/android Dalvik/2.1.0']);
  });

  test('an INCY link: INCY first, then Orbit, v2rayNG, Happ', () async {
    final p = _panel((agent) => agent.startsWith('v2rayNG/') ? _json(_xrayJson) : _json(_accountInfo));
    final r = await p.repo.fetch(_url, client: PanelClient.incy, retry: true);
    expect((r.client, r.retry), (PanelClient.v2rayng, true));
    expect(p.agents, ['INCY/3.3.9/android Dalvik/2.1.0', 'Orbit/1.8.0 (android)', 'v2rayNG/1.10.16']);
  });

  test('a Happ link the panel serves to INCY only: Happ, Orbit, v2rayNG, INCY', () async {
    final p = _panel(
      (agent) => agent.startsWith('INCY/')
          ? _json(_xrayJson, headers: {'subscription-userinfo': 'upload=0; download=0; total=42949672960; expire=1793650015'})
          : _json(_accountInfo),
    );
    final r = await p.repo.fetch(_url, client: PanelClient.happ, retry: true);
    expect(r.client, PanelClient.incy);
    expect(r.info.total, 42949672960);
    expect(p.agents, ['Happ/3.24.1', 'Orbit/1.8.0 (android)', 'v2rayNG/1.10.16', 'INCY/3.3.9/android Dalvik/2.1.0']);

    // a refresh with what was remembered goes straight to it
    p.agents.clear();
    expect((await p.repo.fetch(_url, client: r.client, retry: r.retry)).client, PanelClient.incy);
    expect(p.agents, ['INCY/3.3.9/android Dalvik/2.1.0']);
  });

  test('every app refused: the first app\'s error, after asking each once', () async {
    final p = _panel((_) => http.Response('not found', 404));
    await expectLater(
      p.repo.fetch(_url, client: PanelClient.happ, retry: true),
      throwsA(isA<SubscriptionException>().having((e) => e.message, 'message', 'Панель ответила 404')),
    );
    expect(p.agents, hasLength(4));
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

  test('a Happ link behind a redirect page: the subscription inside is asked for as Happ', () async {
    // encrypted with the bundled crypt key: https://sub.example.com/happ-crypt1
    const happ =
        'happ://crypt/N0XSrBGjaeOipUDxdo4w1EcvzeomVzQFtTFYjBH_gnYkXJmMNCK68csSd27RfXezf1kAeoT6frpay-JnxhTaoAxqyNAw4A5W1kD2udhjsnvLGVzM2XXhyVvltJY75A82bqvPHuaJ0GA38HcuJrbVJ2_rztQkzND7lZRwvaFAs6I';
    final asked = <String>[];
    final repo = SubscriptionRepo(
      'Orbit/1.8.0 (android)',
      httpClient: () => MockClient((request) async {
        final agent = request.headers['User-Agent'] ?? '';
        asked.add('${request.url.host} $agent');
        if (request.url.host == 'happ.example.com') {
          return http.Response('<script>location.href = "$happ";</script>', 200, headers: {'content-type': 'text/html'});
        }
        return agent.startsWith('Happ/') ? _json(_xrayJson) : _json(_accountInfo);
      }),
    );
    final r = await repo.fetch('https://happ.example.com/t/abc');
    expect((r.client, r.retry), (PanelClient.happ, true));
    expect(r.url, 'https://sub.example.com/happ-crypt1');
    expect(asked, ['happ.example.com Orbit/1.8.0 (android)', 'sub.example.com Happ/3.24.1']);
  });

  test('the app a link starts with', () {
    expect(WrappedLink.clientFor('happ://crypt5/abc'), PanelClient.happ);
    expect(WrappedLink.clientFor('happ://add/https://a.example'), PanelClient.happ);
    expect(WrappedLink.clientFor('incy://crypt1/abc'), PanelClient.incy);
    expect(WrappedLink.clientFor('https://a.example/sub'), PanelClient.orbit);
  });

  test('stored names map back, unknown ones fall back to Orbit', () {
    expect(PanelClient.fromName('incy'), PanelClient.incy);
    expect(PanelClient.fromName('happ'), PanelClient.happ);
    expect(PanelClient.fromName(null), PanelClient.orbit);
    expect(PanelClient.fromName('something'), PanelClient.orbit);
  });
}
