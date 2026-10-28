import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/happ_link.dart';

void main() {
  final keys = File(HappLink.asset).readAsStringSync();

  test('happ://crypt5: the salted vector from happ-decryptor', () {
    // from github.com/LeeeeT/happ-decryptor (test/crypt5.test.js)
    const link =
        'happ://crypt5/fzvdO4bMOfTWNaB3taWRhRaF64soexaE9dm3ZlLK0Rke9Rz3BG1f9gmj4tSDpjRSWWdX5G6oaaQK9Gs+fdJPWNXIF08BsaeifWtfTlCvC/nSWDv0ZrofgJXkQ8MlUk63CoJkt7RvXAfablYXb/cYWEZJQkDMyMaE5/1KegAbWVWVI60MPqDylUyYoLtOeOOX9amvELecOZ4kKz1QVqgE9uCBz3py+3Ghr1iVGKOhFwb98OFP+j0tGvDo/3d609DVq3RwBGXu1ogZ7PTc3/A5IlaA3Hff5IlVujozQ3ywmQBsTGd+l3AHJAX1oDbPkRSSwg7Y7hl3AKXKpZsEhMzPbJY8UxZ7GmVsxeROLopVx85ACqakzg+ZZwdZslfKgdRzUmL9Mv895HDOHE3tbh6qnDhE9Ew/Epx1iBCb2HjorOLDBluH8ztdL9mdUX+turjC4GLN0YR55P3H23A0W5zl0di5YfrI2nUBKxh30lUVG9NbqYKlwxgmhxAUZrQ6cnFGF2VuZ9VJLQ3sQ8rqXTtfau8ySbu770Hd6vVEun8aSJm4W4M0DagKbORL4A4M6Cuf1v/jj7EWhA9yhhcSuxkc6WUWMGYRraWBM9vSrSbjeT1U69a3n9T56M/TOJWf4z8fXrHRnCR1tfzwrjHiOJfZGiKvbAd4k6f+VADYpLdCq+ornEElv7V0sByfwPTgep+Q33Qkl67ArHpmbZDcCyWkGz0BoUzGJFe58YiS/oNFVdufbuDnFd1ArAVMztJJJbxlo4Is48+Iof=ff';
    expect(HappLink.decryptWith(' $link ', keys), 'https://example.com/sub');

    // one character changed: the Poly1305 tag no longer matches
    final payload = link.substring('happ://crypt5/'.length);
    final c = payload[200] == 'B' ? 'C' : 'B';
    final tampered = 'happ://crypt5/${payload.substring(0, 200)}$c${payload.substring(201)}';
    expect(() => HappLink.decryptWith(tampered, keys), throwsA(isA<HappLinkException>()));
  });

  test('happ://crypt and crypt4: RSA blocks, URL-safe base64 without padding', () {
    // encrypted with the public halves of the bundled keys
    const crypt1 =
        'happ://crypt/N0XSrBGjaeOipUDxdo4w1EcvzeomVzQFtTFYjBH_gnYkXJmMNCK68csSd27RfXezf1kAeoT6frpay-JnxhTaoAxqyNAw4A5W1kD2udhjsnvLGVzM2XXhyVvltJY75A82bqvPHuaJ0GA38HcuJrbVJ2_rztQkzND7lZRwvaFAs6I';
    const crypt4 =
        'happ://crypt4/cMywBZKRWMrNrnkhs2OWfG92Ft6FAmEaW8zNzR9eYViWWtdiAdrCg_3Zvx9LWgoKZm_zUDaFxN-lkb3Ob_w27I_xtLm286ATiwrKfXRPA_P36dEeU-6bZGoLq7gn-dWMiK40X-wNTBJPQN921KrtOFVb9KZcvcK1Y3U3OwqOpl-74HSUbAsTift3LBDJnxEdcPaB51P35f7BbBOuUHvOM8ulYv6Geys5vkEEL4V-dWYowlkcKdz7VE1Y4bY7euZ8md5u_V3hxXmKbUhUi5rxr7EVbTLbKNm_ek9OvXNEew2NrTe8TUY0zWBaj72jRTUVxWt47TPN_LOSIPhwEJAz3EtTzXMAFQ3SMyDVjG1XWjnpuj5BR-besDHdACG-BVFf7liSki8mHMDNOtETYBUJr0d24_PCuFPS7xgzfAOt7FBJ8y9fdXiRmNapH_mIO39gDapnLwoARXcbeD2LSUjA5IBawFu4o02ROWBZhIR-3BDcnMYcDHJjfGNL79zqh5RhOJD4MMvezchwsgMCjd96wLoY79sMxtrTSwXTp9YaeI22WVUO7-SvSWjR1FTjJfvy_5eOxYR3OA9jz1U1CrODqEm9oHViHKz0Ykz9d-q3FXkJ6LhZhiLJJqgfseXft5Nes5sbRrDQhd4dvF2Yp8_u_yS03fRqRGNX6nxfPbQAel0';
    expect(HappLink.decryptWith(crypt1, keys), 'https://sub.example.com/happ-crypt1');
    expect(HappLink.decryptWith(crypt4, keys), 'https://sub.example.com/happ-crypt4');
    // cut short: no longer a whole RSA block
    expect(() => HappLink.decryptWith(crypt4.substring(0, crypt4.length - 8), keys), throwsA(isA<HappLinkException>()));
  });

  test('not happ links, garbage and unknown crypt5 keys', () {
    expect(HappLink.matches('  HAPP://crypt5/abc'), isTrue);
    expect(HappLink.matches('https://sub.example.com'), isFalse);
    expect(HappLink.matches('incy://crypt1/abc'), isFalse);
    for (final bad in ['happ://crypt5/AAAA', 'happ://crypt9/abc', 'happ://crypt2/!!!', 'happ://crypt3/', 'happ://crypt5/AAAAAAAAAAAAAAAAAAAAAAAA']) {
      expect(() => HappLink.decryptWith(bad, keys), throwsA(isA<HappLinkException>()), reason: bad);
    }
  });
}
