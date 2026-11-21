import 'dart:io';

import 'package:ccloud/core/platform_identity.dart';
import 'package:ccloud/core/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each OS maps to one exact display string', () {
    expect(appPlatformFor('windows'), AppPlatform.windows);
    expect(appPlatformFor('Windows'), AppPlatform.windows);
    expect(appPlatformFor('android'), AppPlatform.android);
    expect(appPlatformFor('macos'), AppPlatform.macos);
    expect(appPlatformFor('ios'), AppPlatform.ios);
    expect(appPlatformFor('linux'), AppPlatform.linux);
    expect(appPlatformFor('fuchsia'), AppPlatform.unknown);

    expect(platformDisplayName(AppPlatform.windows), 'نسخه ویندوز');
    expect(platformDisplayName(AppPlatform.android), 'نسخه اندروید');
    expect(platformDisplayName(AppPlatform.macos), 'نسخه مک (macOS)');
    expect(platformDisplayName(AppPlatform.ios), 'نسخه iOS');
    expect(platformDisplayName(AppPlatform.linux), 'نسخه لینوکس');
    expect(platformDisplayName(AppPlatform.unknown), 'نسخه نامشخص');
  });

  test('this macOS host produces the macOS label through the real path', () {
    expect(Platform.isMacOS, isTrue);
    final identity = PlatformIdentity.forCurrentOs(version: '1.0.6');
    expect(identity.platform, AppPlatform.macos);
    expect(identity.displayName, 'نسخه مک (macOS)');
    expect(identity.versionLabel, 'نسخه مک (macOS) • ۱.۰.۶');
  });

  test('version labels stay OS-correct and omit an empty version', () {
    final windows = PlatformIdentity(
      platform: AppPlatform.windows,
      version: '2.1.0',
    );
    expect(windows.versionLabel, 'نسخه ویندوز • ۲.۱.۰');

    const empty = PlatformIdentity(platform: AppPlatform.android, version: ' ');
    expect(empty.versionLabel, 'نسخه اندروید');
  });

  test('feature blurb names only the running platform', () {
    expect(
      platformFeatureBlurb(AppPlatform.android),
      contains('تلویزیون اندروید'),
    );
    expect(platformFeatureBlurb(AppPlatform.windows), contains('ویندوز'));
    expect(platformFeatureBlurb(AppPlatform.macos), contains('مک'));
    for (final platform in [
      AppPlatform.windows,
      AppPlatform.macos,
      AppPlatform.ios,
      AppPlatform.linux,
    ]) {
      expect(
        platformFeatureBlurb(platform),
        isNot(contains('اندروید')),
        reason: '$platform must not claim to be Android',
      );
    }
  });

  test('player key gate yields only on TV with a focused child', () {
    expect(
      playerYieldsKeysToFocusedChild(
        isTv: true,
        hasPrimaryFocus: true,
        rootHasPrimaryFocus: false,
      ),
      isTrue,
    );
    expect(
      playerYieldsKeysToFocusedChild(
        isTv: true,
        hasPrimaryFocus: true,
        rootHasPrimaryFocus: true,
      ),
      isFalse,
    );
    expect(
      playerYieldsKeysToFocusedChild(
        isTv: true,
        hasPrimaryFocus: false,
        rootHasPrimaryFocus: false,
      ),
      isFalse,
    );
    expect(
      playerYieldsKeysToFocusedChild(
        isTv: false,
        hasPrimaryFocus: true,
        rootHasPrimaryFocus: false,
      ),
      isFalse,
    );
  });
}
