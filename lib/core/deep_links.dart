import 'dart:async';

import 'package:flutter/services.dart';

/// happ:// and incy:// links Orbit was opened with («Открыть в приложении»). MainActivity keeps
/// the latest one and says "available"; [take] fetches it once, so none is handled twice.
abstract class DeepLinks {
  static const _channel = MethodChannel('orbit/links');
  static final _available = StreamController<void>.broadcast();
  static var _listening = false;

  /// Fires when a link arrives while Orbit is open; call [take] then.
  static Stream<void> get available {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'available') _available.add(null);
      });
    }
    return _available.stream;
  }

  /// The waiting link, if any; null after it was taken.
  static Future<String?> take() async {
    try {
      final link = await _channel.invokeMethod<String>('take');
      return link == null || link.trim().isEmpty ? null : link.trim();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null; // tests, other platforms
    }
  }
}
