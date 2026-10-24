// The app's GitHub releases: tags to builds, which is newer, checksums
// and the change log shown before and after an update.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/app_release.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:openlib/services/upgrade_detector.dart';

String _body(String change, {String sha = ''}) => 'Commit: abc1234\n\n'
    'Changes since v1.7.2-build.34:\n- $change (a932d17)\n\n'
    '${sha.isEmpty ? '' : 'SHA-256: `$sha`\n'}';

void main() {
  group('AppBuild', () {
    test('reads release tags, stored versions and plain versions', () {
      final tag = AppBuild.tryParse('v1.7.2-build.35')!;
      expect((tag.major, tag.minor, tag.patch, tag.build), (1, 7, 2, 35));
      expect(tag.label, '1.7.2 (build 35)');
      expect(AppBuild.tryParse('1.7.2+35'), tag);
      expect(AppBuild.tryParse('1.7.2')!.build, 0);
      expect(AppBuild.tryParse('1.7.2-beta.1')!.preRelease, 'beta.1');
      expect(AppBuild.tryParse('nightly'), isNull);
      expect(AppBuild.of('1.7.2', '36').stored, '1.7.2+36');
    });

    test('orders by version, then build; a pre-release comes first', () {
      final b35 = AppBuild.tryParse('v1.7.2-build.35')!;
      final b36 = AppBuild.tryParse('v1.7.2-build.36')!;
      expect(b36 > b35, isTrue);
      expect(AppBuild.tryParse('1.8.0')! > b36, isTrue);
      expect(AppBuild.tryParse('1.7.2')! < b35, isTrue);
      expect(AppBuild.tryParse('1.7.3-beta')! < AppBuild.tryParse('1.7.3')!,
          isTrue);
    });

    test('the upgrade check sees a new build of the same version', () {
      expect(UpgradeDetector.compareVersions('1.7.2', '1.7.2+36'), lessThan(0));
      expect(UpgradeDetector.compareVersions('1.7.2+35', '1.7.2+36'),
          lessThan(0));
      expect(UpgradeDetector.compareVersions('1.7.2+36', '1.7.2+36'), 0);
      expect(UpgradeDetector.compareVersions('1.0.9', '1.0.10'), lessThan(0));
    });
  });

  test('reads the checksum and the change lines of a description', () {
    final sha = 'a' * 64;
    final body = _body('fix(translation): stop the crash', sha: sha);
    expect(releaseSha256(body), sha);
    expect(releaseChanges(body), ['fix(translation): stop the crash']);
    expect(releaseSha256('no checksum'), isNull);
  });

  test('change log: builds after the installed one, newest first, limited',
      () {
    ReleaseNotes r(int build, String change) => (
          build: AppBuild(1, 7, 2, build: build),
          body: _body(change),
          publishedAt: DateTime(2026, 10, build),
        );
    final releases = [r(33, 'a'), r(34, 'b'), r(35, 'c'), r(36, 'd')];
    final log = changeLog(releases,
        after: const AppBuild(1, 7, 2, build: 33),
        upTo: const AppBuild(1, 7, 2, build: 35));
    expect(log, '### 1.7.2 (build 35)\n- c\n\n### 1.7.2 (build 34)\n- b');
    expect(changeLog(releases, limit: 1), '### 1.7.2 (build 36)\n- d');
    expect(changeLog(releases, after: const AppBuild(1, 7, 2, build: 36)), '');
  });

  test('a GitHub release: build, label, APK and its size, no checksum file',
      () {
    final release = ReleaseInfo.fromJson({
      'tag_name': 'v1.7.2-build.35',
      'name': 'LightLib 1.7.2 (build 35)',
      'body': _body('x', sha: 'b' * 64),
      'html_url': 'https://github.com/4rNe5/LightLib/releases/tag/v1.7.2-build.35',
      'prerelease': false,
      'published_at': '2026-10-23T14:36:07Z',
      'assets': [
        {
          'name': 'LightLib-1.7.2-build.35-arm64.apk',
          'size': 139816949,
          'browser_download_url': 'https://example.com/a.apk',
        },
        {
          'name': 'LightLib-1.7.2-build.35-arm64.apk.sha256',
          'size': 100,
          'browser_download_url': 'https://example.com/a.apk.sha256',
        },
      ],
    });
    expect(release.build, const AppBuild(1, 7, 2, build: 35));
    expect(release.label, '1.7.2 (build 35)');
    expect(release.downloadUrls['android-arm64'], 'https://example.com/a.apk');
    expect(release.assetSizes['https://example.com/a.apk'], 139816949);
    expect(release.sha256, 'b' * 64);
  });
}
