/// One past (or currently running) mock session, recorded natively by the
/// MockingService so sessions started from tiles/widgets are captured too.
class MockHistoryEntry {
  final String mode; // 'fixed' | 'route'
  final String label;
  final String fromLabel;
  final String toLabel;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final int plannedDurationSeconds;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? arrivedAt;
  final bool arrived;

  const MockHistoryEntry({
    required this.mode,
    required this.label,
    this.fromLabel = '',
    this.toLabel = '',
    this.latitude = 0,
    this.longitude = 0,
    this.distanceMeters = 0,
    this.plannedDurationSeconds = 0,
    required this.startedAt,
    this.endedAt,
    this.arrivedAt,
    this.arrived = false,
  });

  bool get isRoute => mode == 'route';
  bool get isRunning => endedAt == null;

  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt);

  factory MockHistoryEntry.fromJson(Map<String, dynamic> json) {
    DateTime? fromMillis(dynamic value) {
      final millis = (value as num?)?.toInt() ?? 0;
      return millis <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(millis);
    }

    return MockHistoryEntry(
      mode: json['mode'] ?? 'fixed',
      label: json['label'] ?? '',
      fromLabel: json['fromLabel'] ?? '',
      toLabel: json['toLabel'] ?? '',
      latitude: (json['lat'] as num?)?.toDouble() ?? 0,
      longitude: (json['lng'] as num?)?.toDouble() ?? 0,
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      plannedDurationSeconds:
          (json['durationSeconds'] as num?)?.toInt() ?? 0,
      startedAt:
          fromMillis(json['startedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: fromMillis(json['endedAt']),
      arrivedAt: fromMillis(json['arrivedAt']),
      arrived: json['arrived'] == true,
    );
  }
}
