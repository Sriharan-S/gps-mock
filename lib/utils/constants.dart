class AppConstants {
  // Injected by CI at build time (see .github/workflows/android_release.yml).
  static const String googleMapsApiKey = "API_KEY_PLACEHOLDER";

  // GPS Mock is the testing companion for "My Globe", a maps & navigation
  // project. The free OSM-based services below require a descriptive
  // User-Agent identifying the caller.
  static const String userAgent =
      "gps-mock/2.0 (https://github.com/Sriharan-S/gps-mock; "
      "location testing tool for the My Globe navigation app)";

  static const String photonBaseUrl = "https://photon.komoot.io/api/";
  static const String osrmRouteBaseUrl =
      "https://router.project-osrm.org/route/v1/driving/";

  static String getStaticMapUrl(double lat, double lng) {
    return "https://maps.googleapis.com/maps/api/staticmap?center=$lat,$lng&zoom=15&size=100x100&key=$googleMapsApiKey";
  }
}
