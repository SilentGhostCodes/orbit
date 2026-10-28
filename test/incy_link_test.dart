import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/incy_link.dart';

void main() {
  test('incy://crypt1 links: INCY\'s pinned test vector and a named one', () {
    // from github.com/INCY-DEV/incy-link-encoder (go/incylink_test.go)
    const pinned =
        'incy://crypt1/AAECAwQFBgcICQoLNyIQL3rDwRZqnyoD8pGKSLXP6o8NdSXQVSSALNbbUyIr__tWGFUexdIfKvvmDnuDGbmBvuppfNef6aKNZUwOm4c-Sg';
    expect(IncyLink.decrypt(pinned), (url: 'https://sub.example.com/test-vector', name: null));
    // made with their EncryptLinkDeterministic
    const named =
        'incy://crypt1/AQIDBAUGBwgJCgsMoQlKOOfeDefPqE4S3B1seze0i9a9TqsU_r1cT-PUZetDTh76ju_TNDz7NP-XW2K1MpmpkhYZeOgmU8FRca3YoMsDOFnhquen2Q';
    expect(IncyLink.decrypt(' $named/ '), (url: 'https://sub.example.com/a', name: 'Ghost VPN'));
    // tampered
    expect(IncyLink.decrypt(pinned.replaceFirst('AAEC', 'AAED')), isNull);
    expect(IncyLink.decrypt('https://sub.example.com'), isNull);
  });
}
