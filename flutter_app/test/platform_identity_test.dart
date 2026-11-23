import 'dart:io';

import 'package:ccloud/core/platform_identity.dart';
import 'package:ccloud/core/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  test(
    'this macOS host produces the macOS label through the real path',
    () {
      final identity = PlatformIdentity.forCurrentOs(
        version: '1.0.6',
        buildNumber: '22',
      );
      expect(identity.platform, AppPlatform.macos);
      expect(identity.displayName, 'نسخه مک (macOS)');
      expect(identity.versionLabel, 'نسخه مک (macOS) • ۱.۰.۶ (۲۲)');
    },
    // The suite also runs on Windows and Linux; only a macOS host can assert
    // the real `Platform.operatingSystem` path. The OS→string mapping above is
    // covered independently of the host.
    skip: !Platform.isMacOS,
  );

  test(
    'version labels stay OS-correct, add the build, and omit empty parts',
    () {
      final windows = PlatformIdentity(
        platform: AppPlatform.windows,
        version: '2.1.0',
      );
      expect(windows.versionLabel, 'نسخه ویندوز • ۲.۱.۰');

      final windowsWithBuild = PlatformIdentity(
        platform: AppPlatform.windows,
        version: '2.0.0',
        buildNumber: '22',
      );
      expect(windowsWithBuild.versionLabel, 'نسخه ویندوز • ۲.۰.۰ (۲۲)');

      final whitespaceBuild = PlatformIdentity(
        platform: AppPlatform.windows,
        version: '2.0.0',
        buildNumber: ' ',
      );
      expect(whitespaceBuild.versionLabel, 'نسخه ویندوز • ۲.۰.۰');

      const emptyVersion = PlatformIdentity(
        platform: AppPlatform.android,
        version: ' ',
        buildNumber: '22',
      );
      expect(emptyVersion.versionLabel, 'نسخه اندروید');
    },
  );

  test('load reads the version and build from package metadata', () async {
    PackageInfo.setMockInitialValues(
      appName: 'CCloud',
      packageName: 'com.ccloud.ccloud',
      version: '2.0.0',
      buildNumber: '22',
      buildSignature: '',
    );

    final identity = await PlatformIdentity.load();

    expect(identity.version, '2.0.0');
    expect(identity.buildNumber, '22');
    expect(identity.versionLabel, '${identity.displayName} • ۲.۰.۰ (۲۲)');
    expect(PlatformIdentity.current, same(identity));
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

  test('a dismissed next-episode offer is not revived by resume', () {
    bool offer({
      bool completed = true,
      int countdown = 0,
      bool dismissed = false,
      bool hasUpcoming = true,
      bool autoPlayNextEpisode = true,
    }) => shouldOfferAutoNextOnResume(
      completed: completed,
      countdown: countdown,
      dismissed: dismissed,
      hasUpcoming: hasUpcoming,
      autoPlayNextEpisode: autoPlayNextEpisode,
    );

    expect(offer(), isTrue);
    expect(offer(dismissed: true), isFalse);
    expect(offer(completed: false), isFalse);
    expect(offer(countdown: 7), isFalse);
    expect(offer(hasUpcoming: false), isFalse);
    expect(offer(autoPlayNextEpisode: false), isFalse);
  });
}
