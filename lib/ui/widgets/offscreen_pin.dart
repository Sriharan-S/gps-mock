import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shown when a marker has been panned out of view: a pill parked on the edge
/// of the map nearest it, with an arrow pointing at it and how far away it is.
/// Tapping brings the map back.
///
/// [angle] is the on-screen direction to the marker in radians, measured
/// clockwise from straight up.
class OffscreenPinIndicator extends StatelessWidget {
  const OffscreenPinIndicator({
    super.key,
    required this.area,
    required this.angle,
    required this.distanceLabel,
    required this.color,
    required this.onColor,
    required this.onTap,
    this.label = '',
  });

  /// The region of the map the pill may sit inside (excludes the search bar
  /// and the deck).
  final Rect area;
  final double angle;
  final String distanceLabel;

  /// Short badge text — a stop number, "Start", "End" — or empty for a plain
  /// direction pill.
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  static const _height = 36.0;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label.isNotEmpty;
    // Wider when a badge shares the pill with the distance.
    final halfWidth = hasLabel ? 76.0 : 60.0;
    final center = area.center;

    // Walk out from the centre along the direction until the ray leaves the
    // area, so the pill lands on the edge closest to the marker. The inset
    // keeps the whole pill on screen rather than half of it hanging off.
    final dx = math.sin(angle);
    final dy = -math.cos(angle);
    final inset = Rect.fromLTRB(
      area.left + halfWidth + 8,
      area.top + _height / 2 + 8,
      area.right - halfWidth - 8,
      area.bottom - _height / 2 - 8,
    );
    final scaleX = dx.abs() < 1e-6
        ? double.infinity
        : (dx > 0 ? inset.right - center.dx : center.dx - inset.left) / dx.abs();
    final scaleY = dy.abs() < 1e-6
        ? double.infinity
        : (dy > 0 ? inset.bottom - center.dy : center.dy - inset.top) / dy.abs();
    final scale = math.max(0.0, math.min(scaleX, scaleY));
    final position = center + Offset(dx * scale, dy * scale);

    final describedAs = hasLabel ? '$label, ' : '';
    return Positioned(
      left: position.dx - halfWidth,
      top: position.dy - _height / 2,
      child: Semantics(
        button: true,
        label: '$describedAs$distanceLabel off screen. '
            'Tap to bring the map back to it.',
        child: Tooltip(
          message: hasLabel ? '$label · $distanceLabel' : distanceLabel,
          child: Material(
            color: color,
            shape: const StadiumBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: SizedBox(
                height: _height,
                width: halfWidth * 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The arrow points north at angle 0, so rotating it by the
                    // bearing aims it straight at the marker.
                    Transform.rotate(
                      angle: angle,
                      child: Icon(Icons.navigation, size: 16, color: onColor),
                    ),
                    if (hasLabel) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: onColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        distanceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
