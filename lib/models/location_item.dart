class LocationItem {
  final double latitude;
  final double longitude;
  final String name;
  final String address;

  LocationItem({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.address,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'name': name,
    'address': address,
  };

  factory LocationItem.fromJson(Map<String, dynamic> json) => LocationItem(
    latitude: json['latitude'],
    longitude: json['longitude'],
    name: json['name'],
    address: json['address'],
  );
}
