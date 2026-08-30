import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A release published on GitHub that is newer than what is installed.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkSize = 0,
    this.publishedAt,
  });

  /// The tag exactly as GitHub published it, e.g. "v2026-07-29-19".
  final String tag;

  /// Normalised version, e.g. "2.2.0" — the leading "v" of the tag is dropped.
  final String version;
  final String name;
  final String notes;
  final String pageUrl;

  /// Direct download for the release APK, when the release ships one.
  final String? apkUrl;
  final int apkSize;
  final DateTime? publishedAt;

  bool get hasApk => apkUrl != null;

  String get sizeLabel {
    if (apkSize >= 1024 * 1024) {
      return '${(apkSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (apkSize >= 1024) return '${(apkSize / 1024).round()} KB';
    return '$apkSize B';
  }
}

/// Thin wrapper over the app's platform channel for things that aren't about
/// mocking: the installed version, opening links, and handing an APK to the
/// system installer.
class PlatformClient {
  static const _channel = MethodChannel('com.mockgps/service');

  Future<String> installedVersion() async {
    try {
      final info = await _channel.invokeMethod<Map>('getAppVersion');
      return (info?['versionName'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestInstallPermission() async {
    try {
      await _channel.invokeMethod('requestInstallPermission');
    } catch (_) {
      // The settings screen is best-effort.
    }
  }

  Future<void> installApk(String path) =>
      _channel.invokeMethod('installApk', {'path': path});

  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Checks GitHub releases for a newer build, and downloads it on request.
///
/// The check is deliberately cheap and unauthenticated — one call to the
/// public releases endpoint per app start, suppressed entirely while the user
/// has snoozed updates for the day.
class UpdateService {
  UpdateService({PlatformClient? platform})
      : _platform = platform ?? PlatformClient();

  final PlatformClient _platform;
  final http.Client _client = http.Client();

  static const _snoozeKey = 'update_snooze_until';
  static const _seenTagKey = 'update_seen_release_tag';

  PlatformClient get platform => _platform;

  /// Whether the user ticked "don't remind me today" and the day isn't over.
  Future<bool> isSnoozed() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getString(_snoozeKey);
    if (until == null) return false;
    final parsed = DateTime.tryParse(until);
    if (parsed == null) return false;
    return DateTime.now().isBefore(parsed);
  }

  /// Suppresses the update prompt until the start of tomorrow.
  Future<void> snoozeForToday() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snoozeKey, tomorrow.toIso8601String());
  }

  Future<void> clearSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snoozeKey);
  }

  /// Returns the latest release when it is newer than what is installed,
  /// otherwise null. Never throws — a failed check is silent.
  ///
  /// Two comparison strategies, because a release tag is not always a version:
  ///
  /// * When both the tag and the installed `versionName` look like versions
  ///   ("v2.3.0" against "2.1.0"), they are compared numerically.
  /// * Otherwise — this project currently tags by date, e.g. "v2026-07-29-19"
  ///   — a numeric comparison would be meaningless and would flag an update on
  ///   every launch forever. Instead the newest tag is compared with the last
  ///   one this install has seen, which is seeded silently on first run so the
  ///   app never nags about a release the user may already be running.
  /// Set [force] when the user asked to check: the tag-based path then
  /// reports whatever GitHub has rather than staying quiet, because
  /// "you are up to date" would be a guess we cannot actually make.
  Future<AppRelease?> checkForUpdate({bool force = false}) async {
    try {
      final release = await fetchLatestRelease();
      if (release == null) return null;
      final installed = await _platform.installedVersion();

      if (looksLikeVersion(release.tag) && looksLikeVersion(installed)) {
        return isNewer(release.version, installed) ? release : null;
      }

      if (force) return release;

      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString(_seenTagKey);
      if (seen == null) {
        await prefs.setString(_seenTagKey, release.tag);
        return null;
      }
      return seen == release.tag ? null : release;
    } catch (_) {
      return null;
    }
  }

  /// Whether a release's tag can be measured against the installed build.
  /// False for this project's date-style tags, where the prompt has to be
  /// framed as "here is the latest release" rather than "you are behind".
  Future<bool> isComparable(AppRelease release) async {
    final installed = await _platform.installedVersion();
    return looksLikeVersion(release.tag) && looksLikeVersion(installed);
  }

  /// Records that this install is now on [tag], so the tag-based check stops
  /// offering it. Called once the installer has been handed the APK.
  Future<void> markReleaseInstalled(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenTagKey, tag);
  }

  /// Whether a string is a dotted numeric version rather than, say, a date.
  static bool looksLikeVersion(String raw) {
    final cleaned = normalizeVersion(raw);
    if (cleaned.isEmpty) return false;
    return RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(cleaned);
  }

  Future<AppRelease?> fetchLatestRelease() async {
    final response = await _client.get(
      Uri.parse(AppConstants.latestReleaseApi),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': AppConstants.userAgent,
      },
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    return parseRelease(response.body);
  }

  /// Parses GitHub's release JSON, picking the first `.apk` asset if present.
  static AppRelease? parseRelease(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['draft'] == true) return null;
    final tag = (json['tag_name'] as String?) ?? '';
    if (tag.isEmpty) return null;

    Map<String, dynamic>? apk;
    for (final asset in (json['assets'] as List?) ?? const []) {
      final map = asset as Map<String, dynamic>;
      final name = (map['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apk = map;
        break;
      }
    }

    return AppRelease(
      tag: tag,
      version: normalizeVersion(tag),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : tag,
      notes: (json['body'] as String?)?.trim() ?? '',
      pageUrl: (json['html_url'] as String?) ?? AppConstants.releasesUrl,
      apkUrl: apk?['browser_download_url'] as String?,
      apkSize: (apk?['size'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
    );
  }

  /// Strips a leading "v" and any build suffix, so "v2.2.0+4" reads "2.2.0".
  static String normalizeVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    if (plus >= 0) value = value.substring(0, plus);
    return value.trim();
  }

  /// True when [candidate] is a strictly higher version than [installed].
  /// Missing components count as zero, so "2.2" beats "2.1.9".
  static bool isNewer(String candidate, String installed) {
    final a = _parts(candidate);
    final b = _parts(installed);
    if (a.isEmpty) return false;
    if (b.isEmpty) return true;
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int> _parts(String version) {
    final cleaned = normalizeVersion(version);
    if (cleaned.isEmpty) return const [];
    return cleaned
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  /// Downloads the release APK, reporting progress from 0 to 1. Returns the
  /// file path, ready to hand to the installer.
  Future<String> downloadApk(
    AppRelease release, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    final url = release.apkUrl;
    if (url == null) {
      throw const UpdateException('This release has no APK to download.');
    }

    final directory = await getApplicationSupportDirectory();
    final updates = Directory('${directory.path}/updates');
    if (!updates.existsSync()) updates.createSync(recursive: true);
    // One file per version, so a retry reuses the same slot.
    final file = File('${updates.path}/gps-mock-${release.version}.apk');

    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = AppConstants.userAgent;
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw UpdateException('Download failed (HTTP ${response.statusCode}).');
    }

    final total = response.contentLength ?? release.apkSize;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          total > 0 ? (received / total).clamp(0.0, 1.0) : 0,
          received,
          total,
        );
      }
    } finally {
      await sink.close();
    }
    return file.path;
  }

  /// Removes previously downloaded APKs — they are only needed until the
  /// install completes.
  Future<void> cleanUpDownloads() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final updates = Directory('${directory.path}/updates');
      if (updates.existsSync()) updates.deleteSync(recursive: true);
    } catch (_) {
      // Leftovers are harmless.
    }
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
