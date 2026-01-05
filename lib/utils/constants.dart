class AppConstants {
  // TODO: Replace with your actual API Key or retrieve from secure storage
  static const String googleMapsApiKey = "API_KEY_PLACEHOLDER";

  static String getStaticMapUrl(double lat, double lng) {
    return "https://maps.googleapis.com/maps/api/staticmap?center=$lat,$lng&zoom=15&size=100x100&key=$googleMapsApiKey";
  }
}
