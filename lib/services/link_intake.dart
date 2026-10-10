import 'dart:async';

import 'package:flutter/services.dart';

/// Delivers location links and shared text that Android handed to the app —
/// the one it was launched with, and any that arrive while it is open.
class LinkIntake {
  static const _channel = MethodChannel('com.mockgps/links');

  final StreamController<String> _links = StreamController<String>.broadcast();

  Stream<String> get links => _links.stream;

  /// Starts listening and takes any link waiting from the launch. Call once
  /// the UI that handles [links] is subscribed.
  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'linkAvailable') await _take();
    });
    unawaited(_take());
  }

  Future<void> _take() async {
    try {
      final link = await _channel.invokeMethod<String>('takePendingLink');
      if (link != null && link.trim().isNotEmpty) _links.add(link);
    } on PlatformException {
      // Nothing to take.
    } on MissingPluginException {
      // Not on Android (tests).
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _links.close();
  }
}
