class AppConstants {
  // GPS Mock is the testing companion for "My Globe", a maps & navigation
  // project. Every map/geo service used is free and keyless (OpenStreetMap
  // ecosystem); their usage policies require a descriptive User-Agent
  // identifying the caller.
  static const String userAgent =
      "gps-mock/2.0 (https://github.com/Sriharan-S/gps-mock; "
      "location testing tool for the My Globe navigation app)";

  /// Package name sent as the User-Agent by the flutter_map tile layer.
  static const String tileUserAgentPackage = "com.sriharan.gps_mock";

  /// OpenStreetMap raster tiles — free, no API key or account required.
  static const String osmTileUrl = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

  /// Required attribution for OpenStreetMap tiles; must stay visible on the
  /// map screen.
  static const String osmAttribution = "© OpenStreetMap contributors";

  static const String photonBaseUrl = "https://photon.komoot.io/api/";
  static const String osrmRouteBaseUrl =
      "https://router.project-osrm.org/route/v1/driving/";
}
