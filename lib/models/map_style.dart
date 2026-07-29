enum MapStyleId { standard, humanitarian, topographic, satellite, dark }

/// A selectable base-map style. Every entry is a free, keyless tile service;
/// the [attribution] must stay visible whenever the style is shown.
class MapStyle {
  final MapStyleId id;
  final String name;
  final String description;
  final String urlTemplate;
  final List<String> subdomains;
  final String attribution;
  final int maxZoom;

  const MapStyle({
    required this.id,
    required this.name,
    required this.description,
    required this.urlTemplate,
    this.subdomains = const [],
    required this.attribution,
    required this.maxZoom,
  });

  static const List<MapStyle> all = [
    MapStyle(
      id: MapStyleId.standard,
      name: "Standard",
      description: "Clean, familiar streets and labels",
      urlTemplate:
          "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
      subdomains: ["a", "b", "c", "d"],
      attribution: "© OpenStreetMap contributors · © CARTO",
      maxZoom: 20,
    ),
    MapStyle(
      id: MapStyleId.humanitarian,
      name: "Humanitarian",
      description: "High-contrast, detail-rich style",
      urlTemplate: "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
      subdomains: ["a", "b", "c"],
      attribution: "© OpenStreetMap contributors · HOT",
      maxZoom: 19,
    ),
    MapStyle(
      id: MapStyleId.topographic,
      name: "Topographic",
      description: "Terrain, contours and trails",
      urlTemplate: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
      subdomains: ["a", "b", "c"],
      attribution: "© OpenStreetMap · SRTM · OpenTopoMap (CC-BY-SA)",
      maxZoom: 17,
    ),
    MapStyle(
      id: MapStyleId.satellite,
      name: "Satellite",
      description: "Aerial imagery (Esri)",
      urlTemplate:
          "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
      attribution: "© Esri · Maxar · Earthstar Geographics",
      maxZoom: 19,
    ),
    MapStyle(
      id: MapStyleId.dark,
      name: "Dark",
      description: "Google-like night streets with clear labels",
      urlTemplate:
          "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png",
      subdomains: ["a", "b", "c", "d"],
      attribution: "© OpenStreetMap contributors · © CARTO",
      maxZoom: 20,
    ),
  ];

  static MapStyle byId(MapStyleId id) =>
      all.firstWhere((style) => style.id == id);

  /// The style to actually render: "Standard" quietly becomes the dark
  /// basemap in dark theme so the map matches the app (and avoids costly
  /// color filtering); explicit choices are always respected.
  static MapStyle resolve(MapStyleId id, {required bool darkTheme}) {
    if (id == MapStyleId.standard && darkTheme) return byId(MapStyleId.dark);
    return byId(id);
  }
}
