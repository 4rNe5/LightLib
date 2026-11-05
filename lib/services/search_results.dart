// Search results gathered into series and volumes: the libraries list
// every file of every volume on its own, in whatever order; a reader
// looks for "volume 10 of this series, in Japanese, as an EPUB". Only
// what the libraries returned is shown - nothing here invents a volume.

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/core/book_language.dart';
import 'package:openlib/services/annas_archieve.dart' show BookData;

/// What a result's info line says: `Japanese [ja] · EPUB · 3.2MB · 2023 ·
/// 📕 Book (fiction) · 🚀/lgli/zlib` (Anna's Archive) or `Japanese, EPUB,
/// 3 MB, 2023` (the others).
@immutable
class ResultFacts {
  const ResultFacts({
    this.language,
    this.format,
    this.megabytes,
    this.year,
    this.copies = 1,
  });

  /// English name ('Japanese'), or null.
  final String? language;

  /// Upper case (EPUB, PDF), or null.
  final String? format;
  final double? megabytes;
  final int? year;

  /// How many collections hold the file (Anna's `lgli/zlib/...`): more is
  /// a file more often kept, and more often reachable.
  final int copies;
}

const _formats = ['EPUB', 'AZW3', 'MOBI', 'PDF', 'CBZ', 'CBR', 'DJVU', 'FB2', 'TXT', 'DOCX'];

ResultFacts factsOf(String? info) {
  if (info == null || info.trim().isEmpty) return const ResultFacts();
  final upper = info.toUpperCase();
  String? format;
  for (final f in _formats) {
    if (RegExp('(^|[^A-Z0-9])$f([^A-Z0-9]|\$)').hasMatch(upper)) {
      format = f;
      break;
    }
  }
  final size = RegExp(r'(\d+(?:[.,]\d+)?)\s*(KB|MB|GB)', caseSensitive: false)
      .firstMatch(info);
  double? megabytes;
  if (size != null) {
    final n = double.tryParse(size.group(1)!.replaceAll(',', '.')) ?? 0;
    megabytes = switch (size.group(2)!.toUpperCase()) {
      'KB' => n / 1024,
      'GB' => n * 1024,
      _ => n,
    };
  }
  final year = RegExp(r'(?<![\d.])(19\d\d|20\d\d)(?![\d.])').firstMatch(info);
  final collections = RegExp(r'🚀\s*/?([\w/]+)').firstMatch(info);
  return ResultFacts(
    language: bookLanguageName(info),
    format: format,
    megabytes: megabytes,
    year: year == null ? null : int.parse(year.group(1)!),
    copies: collections == null
        ? 1
        : collections.group(1)!.split('/').where((s) => s.isNotEmpty).length,
  );
}

/// A title split into its series and volume.
@immutable
class VolumeOf {
  const VolumeOf(this.series, this.number, [this.label]);

  /// The series name as written (labels and volume removed).
  final String series;

  /// 1, 2, 10.5; null when the title names no volume.
  final double? number;

  /// How to show the volume when it is not a plain number (上, 下).
  final String? label;

  String get display => label ??
      (number == null
          ? ''
          : number == number!.roundToDouble()
              ? '${number!.toInt()}'
              : '$number');
}

String _halfWidth(String s) => String.fromCharCodes(s.runes.map((c) =>
    c >= 0xFF10 && c <= 0xFF19
        ? c - 0xFF10 + 0x30
        : c >= 0xFF21 && c <= 0xFF5A
            ? c - 0xFEE0
            : c == 0x3000
                ? 0x20
                : c));

final _edgeLabel = RegExp(r'^\s*(【[^】]*】|\[[^\]]*\]|〔[^〕]*〕)|(【[^】]*】|\[[^\]]*\]|〔[^〕]*〕)\s*$');
final _trailingParen = RegExp(r'\s*[（(]([^（()）]*)[）)]\s*$');
final _japanese = RegExp(r'[\u3040-\u30FF\u3400-\u9FFF]');
const _parts = {'上': 1.0, '中': 2.0, '下': 3.0, '前': 1.0, '後': 2.0};

/// The series and volume of a library title: `死亡遊戯で飯を食う。10`,
/// `ようこそ実力至上主義の教室へ 2年生編 (3)`, `○○ 第5巻 (MF文庫J)`,
/// `Overlord, Vol. 4`, `○○ 上`.
VolumeOf volumeOf(String title) {
  var t = _halfWidth(title).replaceAll(RegExp(r'\s+'), ' ').trim();
  // Labels at the ends (【電子特典付き】) and publisher labels in
  // brackets go; a bracketed number is the volume.
  double? number;
  String? label;
  for (var before = ''; before != t;) {
    before = t;
    t = t.replaceAll(_edgeLabel, '').trim();
    final paren = _trailingParen.firstMatch(t);
    if (paren != null) {
      final inside = paren.group(1)!.trim();
      final n = RegExp(r'^(?:第|vol\.?\s*|#)?(\d+(?:\.\d+)?)(?:巻)?$',
              caseSensitive: false)
          .firstMatch(inside);
      if (n != null && number == null) number = double.parse(n.group(1)!);
      final part = RegExp(r'^([上中下前後])(?:巻|編)?$').firstMatch(inside);
      if (part != null && number == null) {
        label = part.group(1)!;
        number = _parts[label];
      }
      t = t.substring(0, paren.start).trim();
    }
  }
  if (number == null) {
    final patterns = [
      RegExp(r'[\s,、・:：-]*第\s*(\d+(?:\.\d+)?)\s*巻.*$'),
      RegExp(r'[\s,、・:：-]*(\d+(?:\.\d+)?)\s*巻.*$'),
      RegExp(r'[\s,、・:：-]*vol(?:ume)?\.?\s*(\d+(?:\.\d+)?).*$',
          caseSensitive: false),
      RegExp(r'[\s,、・:：-]*#(\d+(?:\.\d+)?)\s*$'),
      // A number at the very end, or before a subtitle after a space or
      // a dash: 死亡遊戯で飯を食う。10 / 魔女の旅々 5 ～…
      RegExp(r'(?<=[^\x00-\x7F]|\s)\s*(\d{1,3}(?:\.\d)?)\s*(?:[～〜~―\-:：](?!\d).*)?$'),
      // In a Japanese title, a number then a space and a subtitle:
      // ソードアート・オンライン 1 アインクラッド.
      if (_japanese.hasMatch(t))
        RegExp(r'\s(\d{1,3})\s+[^\d\s].*$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m == null || m.start == 0) continue;
      final head = t.substring(0, m.start).trim();
      // 2年生編 3 is volume 3; 2年生編 alone is not a volume.
      if (head.isEmpty) continue;
      number = double.parse(m.group(1)!);
      t = head;
      break;
    }
  }
  if (number == null) {
    final part = RegExp(r'\s*[(（]?([上中下前後])(?:巻|編)?[)）]?\s*$').firstMatch(t);
    if (part != null && part.start > 0) {
      label = part.group(1)!;
      number = _parts[label];
      t = t.substring(0, part.start).trim();
    }
  }
  // Separators left at the end (a dash closing a title, 86―…―, stays).
  t = t.replaceAll(RegExp(r'[\s,、・:：\-]+$'), '').trim();
  return VolumeOf(t.isEmpty ? title.trim() : t, number, label);
}

/// What series titles are compared by: case, spaces and punctuation
/// aside.
String seriesKey(String series) => _halfWidth(series)
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

/// One file and what was read off it.
@immutable
class ResultFile {
  ResultFile(this.book)
      : facts = factsOf(book.info),
        volume = volumeOf(book.title);

  final BookData book;
  final ResultFacts facts;
  final VolumeOf volume;
}

/// How good a file is for a reader who wants [language] books in
/// [format]: the language first, then the format (EPUB before the rest,
/// PDF last of the text formats), how widely it is kept, the newer
/// edition, a sensible size.
int fileScore(ResultFile f, {String? language, String? format}) {
  var score = 0;
  final l = f.facts.language;
  if (language != null) {
    if (l == language) {
      score += 1000;
    } else if (l == null) {
      score += 300;
    }
  }
  final fmt = f.facts.format;
  if (format != null && fmt == format) score += 400;
  score += switch (fmt) {
    'EPUB' => 200,
    'AZW3' || 'MOBI' => 120,
    'CBZ' || 'CBR' => 100,
    'PDF' => 60,
    null => 0,
    _ => 20,
  };
  score += (f.facts.copies.clamp(1, 6) - 1) * 15;
  if (f.facts.year != null) score += (f.facts.year! - 1990).clamp(0, 40);
  final mb = f.facts.megabytes;
  // An empty or broken file is tiny; a light novel EPUB is a few MB.
  if (mb != null && mb < 0.05) score -= 300;
  return score;
}

@immutable
class VolumeGroup {
  const VolumeGroup(this.volume, this.files);
  final VolumeOf volume;

  /// Best first.
  final List<ResultFile> files;
  ResultFile get best => files.first;
}

@immutable
class SeriesGroup {
  const SeriesGroup(this.series, this.volumes, this.others);
  final String series;

  /// In volume order.
  final List<VolumeGroup> volumes;

  /// Files of the series without a volume number.
  final List<ResultFile> others;

  String? get author => volumes.isEmpty
      ? others.first.book.author
      : volumes.first.best.book.author;

  /// The cover of the first volume that has one.
  String? get cover {
    for (final v in volumes) {
      for (final f in v.files) {
        final t = f.book.thumbnail;
        if (t != null && t.isNotEmpty) return t;
      }
    }
    return null;
  }

  int get fileCount =>
      volumes.fold(others.length, (n, v) => n + v.files.length);
}

@immutable
class GroupedResults {
  const GroupedResults(this.series, this.singles);

  /// Series with at least two volumes found, the one with most volumes
  /// (then the best ranked file) first.
  final List<SeriesGroup> series;

  /// Everything else, best first.
  final List<ResultFile> singles;

  bool get hasSeries => series.isNotEmpty;
}

/// [books] (in the library's order) as series and volumes.
GroupedResults groupResults(List<BookData> books,
    {String? language, String? format}) {
  final files = [for (final b in books) ResultFile(b)];
  int score(ResultFile f) => fileScore(f, language: language, format: format);
  final order = {for (var i = 0; i < files.length; i++) files[i]: i};
  int byBest(ResultFile a, ResultFile b) {
    final s = score(b).compareTo(score(a));
    return s != 0 ? s : order[a]!.compareTo(order[b]!);
  }

  final bySeries = <String, List<ResultFile>>{};
  final names = <String, String>{};
  for (final f in files) {
    final key = seriesKey(f.volume.series);
    if (key.isEmpty) continue;
    bySeries.putIfAbsent(key, () => []).add(f);
    names.putIfAbsent(key, () => f.volume.series);
  }

  final series = <SeriesGroup>[];
  final grouped = <ResultFile>{};
  for (final MapEntry(:key, value: members) in bySeries.entries) {
    final numbered = members.where((f) => f.volume.number != null).toList();
    final volumes = <double, List<ResultFile>>{};
    for (final f in numbered) {
      volumes.putIfAbsent(f.volume.number!, () => []).add(f);
    }
    // A series is two volumes or more; one numbered title is a book.
    if (volumes.length < 2) continue;
    final groups = [
      for (final v in volumes.values)
        VolumeGroup((v..sort(byBest)).first.volume, v),
    ]..sort((a, b) => a.volume.number!.compareTo(b.volume.number!));
    // Keep each group's own sort: files of a volume best first.
    for (final g in groups) {
      g.files.sort(byBest);
    }
    final others = members.where((f) => f.volume.number == null).toList()
      ..sort(byBest);
    series.add(SeriesGroup(names[key]!, groups, others));
    grouped.addAll(members);
  }
  series.sort((a, b) {
    final v = b.volumes.length.compareTo(a.volumes.length);
    if (v != 0) return v;
    return score(b.volumes.first.best).compareTo(score(a.volumes.first.best));
  });
  final singles = files.where((f) => !grouped.contains(f)).toList()
    ..sort(byBest);
  return GroupedResults(series, singles);
}

/// The volume numbers as a short list: `1–3, 5, 10`.
String volumeRanges(List<VolumeGroup> volumes) {
  final out = <String>[];
  var i = 0;
  while (i < volumes.length) {
    final v = volumes[i].volume;
    if (v.label != null || v.number != v.number!.roundToDouble()) {
      out.add(v.display);
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < volumes.length &&
        volumes[j + 1].volume.label == null &&
        volumes[j + 1].volume.number == volumes[j].volume.number! + 1) {
      j++;
    }
    out.add(j - i >= 2
        ? '${v.display}–${volumes[j].volume.display}'
        : [for (var k = i; k <= j; k++) volumes[k].volume.display].join(', '));
    i = j + 1;
  }
  return out.join(', ');
}
