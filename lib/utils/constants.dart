class AppConstants {
  // GPS Mock is the testing companion for "My Globe", a maps & navigation
  // project. Every map/geo service used is free and keyless (OpenStreetMap
  // ecosystem); their usage policies require a descriptive User-Agent
  // identifying the caller.
  static const String userAgent =
      "gps-mock/2.0 (https://github.com/Sriharan-S/gps-mock; "
      "location testing tool for the My Globe navigation app)";

  /// Package name identifying this app when fetching raster tiles.
  static const String tileUserAgentPackage = "com.sriharan.gps_mock";

  /// OpenStreetMap raster tiles — free, no API key or account required.
  static const String osmTileUrl = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

  /// Required attribution for OpenStreetMap tiles; must stay visible on the
  /// map screen.
  static const String osmAttribution = "© OpenStreetMap contributors";

  // ----------------------------------------------------------- the project

  /// Who wrote this, and where it lives. Shown in Settings and used by the
  /// in-app updater.
  static const String developerName = "Sriharan S";
  static const String developerGithub = "https://github.com/Sriharan-S";
  static const String repositoryUrl = "https://github.com/Sriharan-S/gps-mock";
  static const String issuesUrl =
      "https://github.com/Sriharan-S/gps-mock/issues";
  static const String releasesUrl =
      "https://github.com/Sriharan-S/gps-mock/releases";
  static const String companionProjectUrl = "https://github.com/Sriharan-S";

  /// Public, unauthenticated GitHub endpoint for the newest release. Rate
  /// limited to 60 requests an hour per IP, which one check per app start
  /// stays comfortably inside.
  static const String latestReleaseApi =
      "https://api.github.com/repos/Sriharan-S/gps-mock/releases/latest";

  static const String photonBaseUrl = "https://photon.komoot.io/api/";
  static const String osrmRouteBaseUrl =
      "https://router.project-osrm.org/route/v1/driving/";
}
