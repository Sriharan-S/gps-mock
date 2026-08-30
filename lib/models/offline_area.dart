import 'package:latlong2/latlong.dart';

/// How big an administrative area is. The level decides which zoom levels are
/// worth downloading and where the area sits in the offline list's tree.
enum AreaLevel { country, state, district, city, spot }

extension AreaLevelInfo on AreaLevel {
  String get label => switch (this) {
        AreaLevel.country => 'Country',
        AreaLevel.state => 'State',
        AreaLevel.district => 'District',
        AreaLevel.city => 'City',
        AreaLevel.spot => 'Area',
      };

  /// Zoom range downloaded for this level. Bigger areas stop at coarser zooms
  /// — a whole country at street zoom would be millions of tiles.
  (double, double) get zoomRange => switch (this) {
        AreaLevel.country => (3, 8),
        AreaLevel.state => (5, 10),
        AreaLevel.district => (7, 12),
        AreaLevel.city => (9, 14),
        AreaLevel.spot => (11, 16),
      };

  /// Photon's `type` values mapped onto our levels.
  static AreaLevel fromOsmType(String? type) => switch (type) {
        'country' => AreaLevel.country,
        'state' => AreaLevel.state,
        'county' || 'district' => AreaLevel.district,
        'city' => AreaLevel.city,
        _ => AreaLevel.spot,
      };
}

/// A geographic box the user asked to have available offline.
class OfflineArea {
  const OfflineArea({
    required this.id,
    required this.name,
    required this.level,
    required this.southWest,
    required this.northEast,
    this.country = '',
    this.state = '',
    this.district = '',
    this.sizeBytes = 0,
    this.styleUrl = '',
  });

  /// The MapLibre offline region id — the handle used to delete it.
  final int id;
  final String name;
  final AreaLevel level;
  final LatLng southWest;
  final LatLng northEast;

  /// Admin ancestry, used to nest the area in the offline list.
  final String country;
  final String state;
  final String district;

  final int sizeBytes;
  final String styleUrl;

  Map<String, dynamic> toMetadata() => {
        'name': name,
        'level': level.name,
        'country': country,
        'state': state,
        'district': district,
        'sizeBytes': sizeBytes,
        'styleUrl': styleUrl,
      };

  OfflineArea copyWith({int? sizeBytes}) => OfflineArea(
        id: id,
        name: name,
        level: level,
        southWest: southWest,
        northEast: northEast,
        country: country,
        state: state,
        district: district,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        styleUrl: styleUrl,
      );

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) return '${(sizeBytes / 1024).round()} KB';
    return '$sizeBytes B';
  }
}

/// One node of the country → state → district → city tree the offline list
/// renders. A node may carry its own downloaded area, or exist only to hold
/// children (a country row above its cities, say).
class AreaNode {
  AreaNode(this.label, this.level);

  final String label;
  final AreaLevel level;
  final List<AreaNode> children = [];
  final List<OfflineArea> areas = [];

  /// Every area at or under this node — what deleting the node removes.
  List<OfflineArea> get allAreas => [
        ...areas,
        for (final child in children) ...child.allAreas,
      ];

  int get totalBytes =>
      allAreas.fold(0, (sum, area) => sum + area.sizeBytes);

  /// Groups [areas] into a tree by their admin ancestry. Areas whose ancestry
  /// the geocoder didn't supply sit at the top level rather than vanishing.
  static List<AreaNode> buildTree(List<OfflineArea> areas) {
    final roots = <String, AreaNode>{};
    final loose = <OfflineArea>[];

    for (final area in areas) {
      if (area.country.isEmpty) {
        loose.add(area);
        continue;
      }
      final country =
          roots.putIfAbsent(area.country, () => AreaNode(area.country, AreaLevel.country));
      if (area.level == AreaLevel.country) {
        country.areas.add(area);
        continue;
      }

      var parent = country;
      if (area.state.isNotEmpty) {
        parent = _child(parent, area.state, AreaLevel.state);
      }
      if (area.level == AreaLevel.state) {
        parent.areas.add(area);
        continue;
      }
      if (area.district.isNotEmpty && area.level != AreaLevel.district) {
        parent = _child(parent, area.district, AreaLevel.district);
      }
      parent.areas.add(area);
    }

    final tree = roots.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    if (loose.isNotEmpty) {
      final other = AreaNode('Other areas', AreaLevel.spot);
      other.areas.addAll(loose);
      tree.add(other);
    }
    return tree;
  }

  static AreaNode _child(AreaNode parent, String label, AreaLevel level) {
    for (final child in parent.children) {
      if (child.label == label) return child;
    }
    final child = AreaNode(label, level);
    parent.children.add(child);
    return child;
  }
}
