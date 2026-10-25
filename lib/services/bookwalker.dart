// What Japan is reading, from BOOK☆WALKER (bookwalker.jp): the weekly
// rankings of light novels, new literature (web novels published as
// books) and manga, and each genre's most popular series. Only books
// published in volumes are listed there - no single chapters or split
// editions - so what shows up is what a library of books can hold.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;

// Project imports:
import 'package:openlib/services/logger.dart';

/// A BOOK☆WALKER category: its search id and ranking path.
enum BookWalkerCategory {
  lightNovel(3, 'ライトノベル'),
  newLiterature(9, '新文芸'),
  manga(2, 'マンガ');

  const BookWalkerCategory(this.id, this.japanese);

  final int id;
  final String japanese;
}

/// A genre tag on BOOK☆WALKER (`qtag`).
class BookWalkerGenre {
  const BookWalkerGenre(this.tag, this.japanese, this.korean, this.english);

  final int tag;
  final String japanese;
  final String korean;
  final String english;

  /// The genre's name for a [languageCode]: Korean, Japanese, else
  /// English.
  String name(String languageCode) => switch (languageCode) {
        'ko' => korean,
        'ja' => japanese,
        _ => english,
      };
}

const bookWalkerGenres = <BookWalkerGenre>[
  BookWalkerGenre(1995, '異世界系作品', '이세계', 'Isekai'),
  BookWalkerGenre(146, 'ファンタジー', '판타지', 'Fantasy'),
  BookWalkerGenre(99, 'ラブコメディ', '러브코미디', 'Romantic comedy'),
  BookWalkerGenre(97, '恋愛', '연애', 'Romance'),
  BookWalkerGenre(1559, 'バトル・アクション', '배틀·액션', 'Action'),
  BookWalkerGenre(77, 'ミステリー', '미스터리', 'Mystery'),
  BookWalkerGenre(55, 'SF', 'SF', 'Science fiction'),
  BookWalkerGenre(79, 'ホラー', '호러', 'Horror'),
  BookWalkerGenre(26, '歴史', '역사', 'History'),
  BookWalkerGenre(82, 'スポーツ', '스포츠', 'Sports'),
  BookWalkerGenre(72, 'アニメ化・実写化', '애니화', 'Adapted to anime'),
  BookWalkerGenre(42, '完結', '완결', 'Completed'),
  BookWalkerGenre(2, '男性向け', '남성향', 'For men'),
  BookWalkerGenre(3, '女性向け', '여성향', 'For women'),
];

/// A book or series on BOOK☆WALKER.
class BookWalkerBook {
  const BookWalkerBook({
    required this.title,
    required this.cover,
    this.url,
    this.author,
  });

  /// As the store writes it (【電子特別版】, volume, label and all).
  final String title;
  final String cover;
  final String? url;
  final String? author;

  /// What to search the libraries for: the series' name alone.
  String get searchQuery => bookSearchQuery(title);
}

/// The series name in a store title, for a library search: labels such
/// as 【電子特別版】, quotes around a series name (『青春ブタ野郎』シリーズ),
/// the label in brackets (（電撃文庫）), the volume and the subtitle go;
/// a library lists the volumes under the series name.
String bookSearchQuery(String title) {
  // Labels at either end (【電子特別版】, 【悲報】); one inside a title
  // (俺の【日記帳】を) is part of it.
  final edgeLabel =
      RegExp(r'^\s*(【[^】]*】|\[[^\]]*\])|(【[^】]*】|\[[^\]]*\])\s*$');
  final trailing = RegExp(
      r'[（(][^）)]*[）)]\s*$|シリーズ\s*$|@COMIC\s*$|【[^】]*】\s*$',
      caseSensitive: false);
  var t = title.replaceAll('　', ' ').trim();
  for (var before = ''; before != t;) {
    before = t;
    t = t.replaceAll(edgeLabel, '').trim();
  }
  // 『青春ブタ野郎』シリーズ（電撃文庫） → 青春ブタ野郎
  final quoted = RegExp(r'^[「『]([^」』]+)[」』]').firstMatch(t);
  if (quoted != null) t = quoted.group(1)!;
  for (var before = ''; before != t;) {
    before = t;
    t = t.replaceAll(trailing, '').trim();
  }
  // The first volume number, space or subtitle mark past the start ends
  // the series name (Re：ゼロ… and 86―… keep their own marks).
  final end = RegExp(r'[0-9０-９]|\s|[～〜~（(＋+：:「『]')
      .firstMatch(t.length > 3 ? t.substring(3) : '');
  if (end != null) t = t.substring(0, 3 + end.start);
  return t.replaceAll(RegExp(r'^[\s、。・―-]+|[\s、。・―-]+$'), '');
}

/// The books of a ranking page: its Product structured data.
List<BookWalkerBook> parseBookWalkerRanking(String html) {
  final books = <BookWalkerBook>[];
  final scripts = RegExp(
          r'<script type="application/ld\+json">\s*(\[.*?\])\s*</script>',
          dotAll: true)
      .allMatches(html);
  for (final m in scripts) {
    final Object? data;
    try {
      data = jsonDecode(m.group(1)!);
    } catch (_) {
      continue;
    }
    if (data is! List) continue;
    for (final item in data) {
      if (item is! Map || item['@type'] != 'Product') continue;
      final name = item['name'];
      final image = item['image'];
      if (name is! String || image is! String || name.isEmpty) continue;
      books.add(BookWalkerBook(
        title: name,
        cover: image,
        url: item['url'] is String ? item['url'] as String : null,
      ));
    }
  }
  return books;
}

/// The books (series, mostly) of a search results page.
List<BookWalkerBook> parseBookWalkerSearch(String html) {
  final document = parse(html);
  final books = <BookWalkerBook>[];
  for (final heading in document.querySelectorAll('h2.o-tile-ttl')) {
    final link = heading.querySelector('a');
    final title = link?.text.trim() ?? '';
    if (title.isEmpty) continue;
    // The tile holding this heading has the cover.
    var tile = heading.parent;
    String? cover;
    for (var i = 0; i < 4 && tile != null && cover == null; i++) {
      final img = tile.querySelector('img[data-original]') ??
          tile.querySelector('img[src*="bookwalker.jp/thumbnail"]');
      cover = img?.attributes['data-original'] ?? img?.attributes['src'];
      tile = tile.parent;
    }
    if (cover == null || cover.isEmpty) continue;
    // A bonus short story sold with a volume is not a book of its own.
    if (_bonus.hasMatch(title)) continue;
    books.add(BookWalkerBook(
      title: title,
      cover: cover,
      url: link?.attributes['href'],
      author: heading.parent
          ?.querySelector('.o-tile-book-author')
          ?.text
          .trim(),
    ));
  }
  return books;
}

final _bonus = RegExp(r'購入特典|ショートストーリー|特典SS');

/// [books] with one book per series (the first, the best ranked): a
/// ranking lists every volume of a popular series.
List<BookWalkerBook> onePerSeries(List<BookWalkerBook> books) {
  final seen = <String>{};
  return [
    for (final b in books)
      if (seen.add(b.searchQuery.toLowerCase())) b,
  ];
}

/// Fetches BOOK☆WALKER pages, each kept for a day.
class BookWalker {
  BookWalker({Dio? dio}) : _dio = dio ?? Dio();

  static final BookWalker instance = BookWalker();

  static const _base = 'https://bookwalker.jp';
  static const _cacheFor = Duration(hours: 24);

  final Dio _dio;
  final AppLogger _logger = AppLogger();
  final Map<String, (DateTime, List<BookWalkerBook>)> _cache = {};

  /// Drops what was kept (the reader asked for the lists again).
  void forget() => _cache.clear();

  /// What sells in [category] now, a series at a time (the store's
  /// popularity order; its rankings list each volume separately).
  Future<List<BookWalkerBook>> popular(BookWalkerCategory category,
          {bool refresh = false}) =>
      _get('$_base/search/?order=rank&qcat=${category.id}',
              parseBookWalkerSearch,
              refresh: refresh)
          .then(onePerSeries);

  /// The most popular series of [category] in [genre].
  Future<List<BookWalkerBook>> genre(
          BookWalkerCategory category, BookWalkerGenre genre,
          {bool refresh = false}) =>
      _get(
          '$_base/search/?order=rank&qcat=${category.id}&qtag=${genre.tag}',
          parseBookWalkerSearch,
          refresh: refresh)
      .then(onePerSeries);

  Future<List<BookWalkerBook>> _get(
      String url, List<BookWalkerBook> Function(String html) parser,
      {bool refresh = false}) async {
    final kept = _cache[url];
    if (!refresh &&
        kept != null &&
        DateTime.now().difference(kept.$1) < _cacheFor) {
      return kept.$2;
    }
    try {
      final response = await _dio.get<String>(url,
          options: Options(
            responseType: ResponseType.plain,
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/125.0 Mobile Safari/537.36',
              'Accept-Language': 'ja,ko;q=0.8,en;q=0.6',
            },
          ));
      final books = parser(response.data ?? '');
      if (books.isEmpty) {
        // The page came but held nothing: its layout changed.
        _logger.warning('BOOK☆WALKER page without books',
            tag: 'BookWalker', metadata: {'url': url});
      } else {
        _cache[url] = (DateTime.now(), books);
      }
      return books;
    } on DioException catch (e) {
      _logger.warning('BOOK☆WALKER request failed',
          tag: 'BookWalker', metadata: {'url': url, 'error': e.message});
      if (kept != null) return kept.$2;
      rethrow;
    }
  }
}
