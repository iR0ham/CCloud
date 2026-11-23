import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'models.dart';

/// The OS the running build actually is. One place decides which name and
/// which sentence the UI may show, so a Windows build can never call itself an
/// Android one and no platform name is compiled in per flavour.
enum AppPlatform { windows, android, macos, ios, linux, unknown }

AppPlatform appPlatformFor(String operatingSystem) {
  return switch (operatingSystem.toLowerCase()) {
    'windows' => AppPlatform.windows,
    'android' => AppPlatform.android,
    'macos' => AppPlatform.macos,
    'ios' => AppPlatform.ios,
    'linux' => AppPlatform.linux,
    _ => AppPlatform.unknown,
  };
}

/// Exact label for every surface that names the platform.
String platformDisplayName(AppPlatform platform) {
  return switch (platform) {
    AppPlatform.windows => 'نسخه ویندوز',
    AppPlatform.android => 'نسخه اندروید',
    AppPlatform.macos => 'نسخه مک (macOS)',
    AppPlatform.ios => 'نسخه iOS',
    AppPlatform.linux => 'نسخه لینوکس',
    AppPlatform.unknown => 'نسخه نامشخص',
  };
}

/// The About sentence stays meaningful on every platform instead of naming
/// Android on a Windows or macOS build.
String platformFeatureBlurb(AppPlatform platform) {
  return switch (platform) {
    AppPlatform.windows => 'رابط کاربری فارسی و راست‌به‌چپ، بهینه برای ویندوز.',
    AppPlatform.android => 'رابط کاربری فارسی و راست‌به‌چپ، بهینه برای گوشی، تبلت و تلویزیون اندروید.',
    AppPlatform.macos => 'رابط کاربری فارسی و راست‌به‌چپ، بهینه برای مک.',
    AppPlatform.ios =>
      'رابط کاربری فارسی و راست‌به‌چپ، بهینه برای آیفون و آیپد.',
    AppPlatform.linux => 'رابط کاربری فارسی و راست‌به‌چپ، بهینه برای لینوکس.',
    AppPlatform.unknown => 'رابط کاربری فارسی و راست‌به‌چپ.',
  };
}

/// Platform name plus the version and build reported by the store package,
/// not from literals in the source.
class PlatformIdentity {
  const PlatformIdentity({
    required this.platform,
    required this.version,
    this.buildNumber = '',
  });

  factory PlatformIdentity.forCurrentOs({
    required String version,
    String buildNumber = '',
    String? operatingSystem,
  }) {
    return PlatformIdentity(
      platform: appPlatformFor(operatingSystem ?? Platform.operatingSystem),
      version: version,
      buildNumber: buildNumber,
    );
  }

  final AppPlatform platform;

  /// `PackageInfo.version` (the pubspec version without the build number).
  final String version;

  /// `PackageInfo.buildNumber` (the global build, e.g. `22`), or empty when
  /// the platform does not report one.
  final String buildNumber;

  String get displayName => platformDisplayName(platform);

  String get versionLabel {
    final trimmedVersion = version.trim();
    if (trimmedVersion.isEmpty) return displayName;
    final trimmedBuild = buildNumber.trim();
    final buildSuffix = trimmedBuild.isEmpty
        ? ''
        : ' (${faDigits(trimmedBuild)})';
    return '$displayName • ${faDigits(trimmedVersion)}$buildSuffix';
  }

  String get featureBlurb => platformFeatureBlurb(platform);

  static PlatformIdentity? _current;

  /// Loaded before `runApp`; before that the label is still OS-correct and
  /// simply omits the version and build.
  static PlatformIdentity get current =>
      _current ?? PlatformIdentity.forCurrentOs(version: '');

  static Future<PlatformIdentity> load() async {
    var version = '';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {
      // A missing platform channel must not block startup; the label stays
      // OS-correct without a version or build.
    }
    final identity = PlatformIdentity.forCurrentOs(
      version: version,
      buildNumber: buildNumber,
    );
    _current = identity;
    return identity;
  }
}
