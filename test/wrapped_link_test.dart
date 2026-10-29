import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/subscription_repo.dart';
import 'package:orbit/data/wrapped_link.dart';

void main() {
  const link = 'happ://crypt5/fzvdO4bMOfTWNaB3taWRhRaF64so+exa/E9dm3ZlLK0Rke9Rz3BG1f9gmj4tSDpjRSWW=ff';

  test('finds a Happ link wherever a redirect page keeps it', () {
    final pages = {
      'script string': '<script>window.location.href = "$link";</script>',
      'escaped slashes': '<script>const u = "${link.replaceAll('/', r'\/')}"; location = u;</script>',
      'unicode escapes': '<script>go("${link.replaceAll('/', r'/').replaceAll(':', r':')}")</script>',
      'button href': '<a class="btn" href="$link">Подключить в Happ</a>',
      'html entities': '<button onclick="location.href=\'${link.replaceAll('/', '&#x2F;').replaceAll(':', '&#58;')}\'">Go</button>',
      'meta refresh': '<meta http-equiv="refresh" content="0;url=$link">',
      'percent-encoded': '<a href="https://example.com/open?u=${Uri.encodeComponent(link)}&x=1">open</a>',
      'atob': '<script>location.href = atob("${base64.encode(utf8.encode(link))}");</script>',
    };
    pages.forEach((name, page) => expect(WrappedLink.findIn(page), link, reason: name));
  });

  test('happ://add/ in a page and unwrapped', () async {
    expect(
      WrappedLink.findIn('<a href="happ://add/https://sub.example.com/a?b=1">x</a>'),
      'happ://add/https://sub.example.com/a?b=1',
    );
    expect(await WrappedLink.unwrap('happ://add/https://sub.example.com/a'), (url: 'https://sub.example.com/a', name: null));
    expect(
      await WrappedLink.unwrap('happ://add/${Uri.encodeComponent('https://sub.example.com/a?b=1')}'),
      (url: 'https://sub.example.com/a?b=1', name: null),
    );
    expect(() => WrappedLink.unwrap('happ://add/ftp://x'), throwsA(isA<SubscriptionException>()));
    expect(await WrappedLink.unwrap('incy://add/https://sub.example.com/i'), (url: 'https://sub.example.com/i', name: null));
    expect(await WrappedLink.unwrap('incy://import/https://sub.example.com/i'), (url: 'https://sub.example.com/i', name: null));
    // a happ:// link that is not a subscription
    expect(() => WrappedLink.unwrap('happ://routing/onadd/abc'), throwsA(isA<SubscriptionException>()));
    expect(await WrappedLink.unwrap('https://sub.example.com/a'), isNull);
  });

  test('encrypted links win over happ://add/, plain pages give nothing', () {
    expect(WrappedLink.findIn('<a href="happ://add/https://a.example">a</a><script>x="$link"</script>'), link);
    expect(WrappedLink.findIn('<h1>Открываем Happ...</h1><button>Подключить в Happ</button>'), isNull);
    expect(WrappedLink.findIn('<a href="https://example.com/%zz">broken escape</a>'), isNull);
    expect(WrappedLink.matches(' happ://crypt4/abc'), isTrue);
    expect(WrappedLink.matches('happ://add/https://a.example'), isTrue);
    expect(WrappedLink.matches('https://happ.example.com/t/abc'), isFalse);
  });
}
