import 'dart:convert';

import 'package:gps_mock/utils/constants.dart';

enum MapStyleId { auto, streets, minimal, dark, satellite }

/// A selectable MapLibre base map. Every entry is a free, keyless style; the
/// [attribution] must stay visible on screen whenever the style is shown.
class MapStyle {
  const MapStyle({
    required this.id,
    required this.name,
    required this.description,
    required this.attribution,
    this.styleUrl,
    this.styleJson,
    this.supports3d = false,
    this.isDark = false,
  }) : assert(styleUrl != null || styleJson != null);

  final MapStyleId id;
  final String name;
  final String description;
  final String attribution;

  /// Remote MapLibre style document, or null when the style is built in-app.
  final String? styleUrl;

  /// Inline MapLibre style document, used for styles we assemble ourselves.
  final String? styleJson;

  /// Whether this style has a `buildings` layer the 3D toggle can extrude.
  final bool supports3d;

  /// Whether the style renders a dark basemap — drives the contrast of the
  /// overlays drawn on top of it.
  final bool isDark;

  /// What to hand to MapLibre's `styleString`.
  String get style => styleJson ?? styleUrl!;

  static const lightUrl = 'https://tiles.immich.cloud/v1/style/light.json';
  static const darkUrl = 'https://tiles.immich.cloud/v1/style/dark.json';

  static const _light = MapStyle(
    id: MapStyleId.auto,
    name: 'Light',
    description: 'Clean daytime streets',
    attribution: AppConstants.osmAttribution,
    styleUrl: lightUrl,
    supports3d: true,
  );

  static const _dark = MapStyle(
    id: MapStyleId.dark,
    name: 'Dark',
    description: 'Night streets with clear labels',
    attribution: AppConstants.osmAttribution,
    styleUrl: darkUrl,
    supports3d: true,
    isDark: true,
  );

  /// The styles offered in the layer picker, in order.
  static final List<MapStyle> all = [
    const MapStyle(
      id: MapStyleId.auto,
      name: 'Auto',
      description: 'Follows the app theme',
      attribution: AppConstants.osmAttribution,
      styleUrl: lightUrl,
      supports3d: true,
    ),
    const MapStyle(
      id: MapStyleId.streets,
      name: 'Streets',
      description: 'Detailed, colourful road map',
      attribution: '© OpenStreetMap contributors · OpenFreeMap',
      styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
    ),
    const MapStyle(
      id: MapStyleId.minimal,
      name: 'Minimal',
      description: 'Muted basemap, data stands out',
      attribution: '© OpenStreetMap contributors · OpenFreeMap',
      styleUrl: 'https://tiles.openfreemap.org/styles/positron',
    ),
    _dark,
    MapStyle(
      id: MapStyleId.satellite,
      name: 'Satellite',
      description: 'Aerial imagery',
      attribution: '© Esri · Maxar · Earthstar Geographics',
      styleJson: _satelliteStyleJson,
      isDark: true,
    ),
  ];

  static MapStyle byId(MapStyleId id) =>
      all.firstWhere((style) => style.id == id, orElse: () => all.first);

  /// The style to actually render. "Auto" resolves to the light or dark
  /// basemap so the map always matches the app theme; every explicit choice
  /// is respected as-is.
  static MapStyle resolve(MapStyleId id, {required bool darkTheme}) {
    if (id != MapStyleId.auto) return byId(id);
    return darkTheme ? _dark : _light;
  }

  /// Esri's World Imagery wrapped in a minimal MapLibre raster style — the
  /// tile service is keyless but publishes no style document of its own.
  static final String _satelliteStyleJson = jsonEncode({
    'version': 8,
    'sources': {
      'esri-imagery': {
        'type': 'raster',
        'tiles': [
          'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'World_Imagery/MapServer/tile/{z}/{y}/{x}',
        ],
        'tileSize': 256,
        'maxzoom': 19,
        'attribution': '© Esri · Maxar · Earthstar Geographics',
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#0b1220'},
      },
      {
        'id': 'esri-imagery',
        'type': 'raster',
        'source': 'esri-imagery',
        'minzoom': 0,
        'maxzoom': 22,
      },
    ],
  });
}
