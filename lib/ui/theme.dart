import 'package:flutter/material.dart';

/// Status colours that sit outside the Material palette — "mocking is live",
/// "stop", and the route waypoint roles. They are defined per brightness so
/// call sites never hardcode `Colors.green.shade700`, which is unreadable on
/// a dark surface.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.live,
    required this.onLive,
    required this.liveContainer,
    required this.onLiveContainer,
    required this.stop,
    required this.onStop,
    required this.origin,
    required this.waypoint,
    required this.destination,
  });

  final Color live;
  final Color onLive;
  final Color liveContainer;
  final Color onLiveContainer;
  final Color stop;
  final Color onStop;
  final Color origin;
  final Color waypoint;
  final Color destination;

  static const light = AppStatusColors(
    live: Color(0xFF116B3C),
    onLive: Colors.white,
    liveContainer: Color(0xFFB8F2CE),
    onLiveContainer: Color(0xFF00210F),
    stop: Color(0xFFB3261E),
    onStop: Colors.white,
    origin: Color(0xFF1B873F),
    waypoint: Color(0xFF1A6FE0),
    destination: Color(0xFFD03535),
  );

  static const dark = AppStatusColors(
    live: Color(0xFF5CD98D),
    onLive: Color(0xFF00391C),
    liveContainer: Color(0xFF00522B),
    onLiveContainer: Color(0xFFB8F2CE),
    stop: Color(0xFFFFB4AB),
    onStop: Color(0xFF690005),
    origin: Color(0xFF5CD98D),
    waypoint: Color(0xFF8AB4F8),
    destination: Color(0xFFFF8A80),
  );

  /// Hex strings for the MapLibre annotation API, which takes CSS colours
  /// rather than Dart [Color]s.
  String get originHex => _hex(origin);
  String get waypointHex => _hex(waypoint);
  String get destinationHex => _hex(destination);
  String get liveHex => _hex(live);

  static String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  @override
  AppStatusColors copyWith({
    Color? live,
    Color? onLive,
    Color? liveContainer,
    Color? onLiveContainer,
    Color? stop,
    Color? onStop,
    Color? origin,
    Color? waypoint,
    Color? destination,
  }) {
    return AppStatusColors(
      live: live ?? this.live,
      onLive: onLive ?? this.onLive,
      liveContainer: liveContainer ?? this.liveContainer,
      onLiveContainer: onLiveContainer ?? this.onLiveContainer,
      stop: stop ?? this.stop,
      onStop: onStop ?? this.onStop,
      origin: origin ?? this.origin,
      waypoint: waypoint ?? this.waypoint,
      destination: destination ?? this.destination,
    );
  }

  @override
  AppStatusColors lerp(covariant AppStatusColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppStatusColors(
      live: mix(live, other.live),
      onLive: mix(onLive, other.onLive),
      liveContainer: mix(liveContainer, other.liveContainer),
      onLiveContainer: mix(onLiveContainer, other.onLiveContainer),
      stop: mix(stop, other.stop),
      onStop: mix(onStop, other.onStop),
      origin: mix(origin, other.origin),
      waypoint: mix(waypoint, other.waypoint),
      destination: mix(destination, other.destination),
    );
  }
}

extension StatusColorsX on ThemeData {
  AppStatusColors get status =>
      extension<AppStatusColors>() ?? AppStatusColors.light;
}

/// The app's Material 3 design system: one seed, one shape scale, and
/// component themes so individual screens never restyle buttons by hand.
class AppTheme {
  const AppTheme._();

  /// Map-blue seed — this is a map tool first.
  static const seed = Color(0xFF2E6BE6);

  /// The corner radius shared by cards, sheets and inputs.
  static const radius = 18.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      extensions: [isDark ? AppStatusColors.dark : AppStatusColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: const StadiumBorder()),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 44),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 3,
        backgroundColor: scheme.surfaceContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
