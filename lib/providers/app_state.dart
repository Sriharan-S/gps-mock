import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gps_mock/services/mock_service_client.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState with ChangeNotifier {
  final MockServiceClient _client = MockServiceClient();
  bool _isMocking = false;
  LatLng _currentLocation = const LatLng(
    37.422,
    -122.084,
  ); // Default to Googleplex
  String _currentAddress = "Tap map to select location";

  List<LocationItem> _favorites = [];

  bool get isMocking => _isMocking;
  LatLng get currentLocation => _currentLocation;
  String get currentAddress => _currentAddress;
  List<LocationItem> get favorites => _favorites;

  AppState() {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favoritesJson = prefs.getStringList('favorites') ?? [];
    _favorites = favoritesJson
        .map((item) => LocationItem.fromJson(jsonDecode(item)))
        .toList();
    notifyListeners();
  }

  Future<void> addFavorite(String name) async {
    final newItem = LocationItem(
      latitude: _currentLocation.latitude,
      longitude: _currentLocation.longitude,
      name: name,
      address: _currentAddress,
    );
    _favorites.add(newItem);
    await _saveFavorites();
    notifyListeners();
  }

  Future<void> removeFavorite(LocationItem item) async {
    _favorites.removeWhere(
      (element) =>
          element.latitude == item.latitude &&
          element.longitude == item.longitude,
    );
    await _saveFavorites();
    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favoritesJson = _favorites
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await prefs.setStringList('favorites', favoritesJson);
  }

  Future<void> checkPermissions() async {
    await [Permission.location, Permission.notification].request();
  }

  void updateLocation(LatLng loc, {String? address}) {
    _currentLocation = loc;
    if (address != null) {
      _currentAddress = address;
    } else {
      _currentAddress =
          "${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}";
    }

    if (_isMocking) {
      _client.startMocking(loc.latitude, loc.longitude);
    }
    notifyListeners();
  }

  Future<void> toggleMocking() async {
    if (_isMocking) {
      await _client.stopMocking();
      _isMocking = false;
    } else {
      await _client.startMocking(
        _currentLocation.latitude,
        _currentLocation.longitude,
      );
      _isMocking = true;
    }
    notifyListeners();
  }

  Future<void> openSettings() async {
    await _client.openDeveloperSettings();
  }
}
