class LocationItem {
  final String id;
  final double latitude;
  final double longitude;
  final String name;
  final String address;

  LocationItem({
    String? id,
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.address,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'name': name,
    'address': address,
  };

  factory LocationItem.fromJson(Map<String, dynamic> json) => LocationItem(
    // Favorites saved before ids existed get a stable, deterministic id so
    // quick-settings tiles and widgets keep pointing at the same favorite.
    id: json['id'] ?? 'legacy_${json['latitude']}_${json['longitude']}',
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    name: json['name'],
    address: json['address'],
  );
}
