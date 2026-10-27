import 'dart:io';

import 'package:orbit/core/native.dart';
import 'package:orbit/data/models.dart';

/// Pings straight to the server, not through it: the app's process is outside the tunnel.
abstract class DirectPing {
  /// Time to open a TCP connection to the server's port, without the name lookup; null on failure.
  static Future<int?> tcp(Server server, {required int timeoutSeconds}) async {
    final endpoint = server.endpoint;
    if (endpoint == null) return null;
    final timeout = Duration(seconds: timeoutSeconds);
    try {
      final addresses = await InternetAddress.lookup(endpoint.host).timeout(timeout);
      if (addresses.isEmpty) return null;
      final watch = Stopwatch()..start();
      final socket = await Socket.connect(addresses.first, endpoint.port, timeout: timeout);
      final delay = watch.elapsedMilliseconds;
      socket.destroy();
      return delay;
    } on Object {
      return null;
    }
  }

  /// One ICMP echo to the server's address; null if none came back. Servers behind a CDN answer
  /// for the CDN's edge, and some hosts drop echoes altogether.
  static Future<int?> icmp(Server server, {required int timeoutSeconds}) async {
    final endpoint = server.endpoint;
    if (endpoint == null) return null;
    try {
      return await Native.icmpPing(endpoint.host, timeoutSeconds: timeoutSeconds);
    } on Object {
      return null;
    }
  }
}
