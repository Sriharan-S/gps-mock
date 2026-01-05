import 'package:flutter/services.dart';

class MockServiceClient {
  static const platform = MethodChannel('com.mockgps/service');

  Future<void> startMocking(double lat, double lng) async {
    try {
      await platform.invokeMethod('startMocking', {'lat': lat, 'lng': lng});
    } on PlatformException catch (e) {
      print("Failed to start mocking: '${e.message}'.");
      rethrow;
    }
  }

  Future<void> stopMocking() async {
    try {
      await platform.invokeMethod('stopMocking');
    } on PlatformException catch (e) {
      print("Failed to stop mocking: '${e.message}'.");
    }
  }

  Future<void> openDeveloperSettings() async {
    try {
      await platform.invokeMethod('openDeveloperSettings');
    } on PlatformException catch (e) {
      print("Failed to open settings: '${e.message}'.");
    }
  }
}
