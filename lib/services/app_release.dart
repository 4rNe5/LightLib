// The app's own releases on GitHub (4rNe5/LightLib): which build a tag
// names, which one is newer, and the change list a release describes.
// Every push to main is released as v<version>-build.<n>, so builds of
// one version differ only in their build number.

/// A version plus build number: `v1.7.2-build.35`, `1.7.2+35`, `1.7.2`.
class AppBuild implements Comparable<AppBuild> {
  const AppBuild(this.major, this.minor, this.patch,
      {this.build = 0, this.preRelease});

  final int major;
  final int minor;
  final int patch;

  /// 0 when the text named none.
  final int build;

  /// A pre-release label other than a build number (`beta.1`), or null.
  final String? preRelease;

  static final _pattern = RegExp(
      r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-build\.(\d+)|\+(\d+))?(?:-([0-9A-Za-z.-]+))?$');

  /// Null when [text] is not a version.
  static AppBuild? tryParse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    int part(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return AppBuild(part(1), part(2), part(3),
        build: int.tryParse(m.group(4) ?? m.group(5) ?? '') ?? 0,
        preRelease: m.group(6));
  }

  /// From the platform's version name and build number.
  static AppBuild of(String version, String buildNumber) {
    final base = tryParse(version) ?? const AppBuild(0, 0, 0);
    return AppBuild(base.major, base.minor, base.patch,
        build: int.tryParse(buildNumber) ?? base.build,
        preRelease: base.preRelease);
  }

  String get version => '$major.$minor.$patch';

  /// `1.7.2 (build 35)`.
  String get label => build > 0 ? '$version (build $build)' : version;

  /// What the upgrade check stores: `1.7.2+35`.
  String get stored => build > 0 ? '$version+$build' : version;

  @override
  int compareTo(AppBuild other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    // A pre-release comes before the release it leads up to.
    if (preRelease == other.preRelease) return 0;
    if (preRelease == null) return 1;
    if (other.preRelease == null) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  bool operator >(AppBuild other) => compareTo(other) > 0;
  bool operator <(AppBuild other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is AppBuild && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build, preRelease);

  @override
  String toString() => label;
}

final _sha256 = RegExp(r'SHA-256:\s*`?([0-9a-fA-F]{64})`?');

/// The APK checksum the release workflow writes into the description.
String? releaseSha256(String body) => _sha256.firstMatch(body)?.group(1);

/// The change lines (`- fix: ...`) of a release description, without the
/// commit hashes the workflow appends.
List<String> releaseChanges(String body) => [
      for (final line in body.split('\n'))
        if (RegExp(r'^\s*[-*]\s+').hasMatch(line))
          line
              .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
              .replaceFirst(RegExp(r'\s*\([0-9a-f]{7,40}\)\s*$'), '')
              .trim(),
    ].where((l) => l.isNotEmpty).toList();

/// A release as far as the changelog needs it.
typedef ReleaseNotes = ({AppBuild build, String body, DateTime publishedAt});

/// Markdown for the releases after [after] up to [upTo] (both null-able:
/// open ends), newest first: one heading per build, its change lines;
/// at most [limit] builds.
String changeLog(Iterable<ReleaseNotes> releases,
    {AppBuild? after, AppBuild? upTo, int? limit}) {
  final picked = releases
      .where((r) =>
          (after == null || r.build > after) &&
          (upTo == null || !(r.build > upTo)))
      .toList()
    ..sort((a, b) => b.build.compareTo(a.build));
  final out = StringBuffer();
  var written = 0;
  for (final r in picked) {
    final changes = releaseChanges(r.body);
    if (changes.isEmpty) continue;
    if (limit != null && written++ >= limit) break;
    out.writeln('### ${r.build.label}');
    for (final c in changes) {
      out.writeln('- $c');
    }
    out.writeln();
  }
  return out.toString().trim();
}
