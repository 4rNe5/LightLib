// A book's glossary: its characters, places and special terms with the
// Korean form every translation uses, and each character's gender. Built
// once per book - candidates found in the text, then sorted and named by
// the translation model in a few short requests - and editable by the
// reader. Only the entries a request's paragraphs contain are sent with
// it. The approach follows Glossarion's glossary system
// (github.com/Shirochi-stack/Glossarion, AGPL-3.0).

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Project imports:
import 'package:openlib/services/epub_package.dart';
import 'package:openlib/services/translation/paragraph_text.dart';

enum GlossaryKind {
  person,
  place,
  term;

  static GlossaryKind? parse(String text) {
    final t = text.trim().toLowerCase();
    if (t.startsWith('person') || t.startsWith('char') || t.contains('인물')) {
      return GlossaryKind.person;
    }
    if (t.startsWith('place') || t.startsWith('loc') || t.contains('장소')) {
      return GlossaryKind.place;
    }
    if (t.startsWith('term') || t.startsWith('word') || t.contains('용어')) {
      return GlossaryKind.term;
    }
    return null;
  }
}

enum GlossaryGender {
  male,
  female,
  unknown;

  static GlossaryGender parse(String text) {
    final t = text.trim().toLowerCase();
    if (t.startsWith('m') || t.contains('남')) return GlossaryGender.male;
    if (t.startsWith('f') || t.contains('여')) return GlossaryGender.female;
    return GlossaryGender.unknown;
  }
}

class GlossaryEntry {
  const GlossaryEntry({
    required this.source,
    required this.target,
    this.reading,
    this.kind = GlossaryKind.person,
    this.gender = GlossaryGender.unknown,
    this.speech,
    this.edited = false,
  });

  /// As written in the book (石井和希, シャーロット).
  final String source;

  /// The Korean every translation uses (이시이 카즈키).
  final String target;

  /// The book's furigana for it, when it has one.
  final String? reading;
  final GlossaryKind kind;
  final GlossaryGender gender;

  /// How a person talks (`polite`, `casual, cheerful`), when known.
  final String? speech;

  /// Changed by the reader: kept when the glossary is made again.
  final bool edited;

  bool get isName => kind != GlossaryKind.term;

  GlossaryEntry copyWith({
    String? target,
    GlossaryKind? kind,
    GlossaryGender? gender,
    String? speech,
    bool? edited,
  }) =>
      GlossaryEntry(
        source: source,
        target: target ?? this.target,
        reading: reading,
        kind: kind ?? this.kind,
        gender: gender ?? this.gender,
        speech: speech ?? this.speech,
        edited: edited ?? this.edited,
      );

  Map<String, Object?> toJson() => {
        'source': source,
        'target': target,
        if (reading != null) 'reading': reading,
        'kind': kind.name,
        'gender': gender.name,
        if (speech != null) 'speech': speech,
        if (edited) 'edited': true,
      };

  static GlossaryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final source = raw['source'];
    final target = raw['target'];
    if (source is! String || target is! String || source.isEmpty) return null;
    return GlossaryEntry(
      source: source,
      target: target,
      reading: raw['reading'] as String?,
      kind: GlossaryKind.values.asNameMap()[raw['kind']] ?? GlossaryKind.term,
      gender: GlossaryGender.values.asNameMap()[raw['gender']] ??
          GlossaryGender.unknown,
      speech: raw['speech'] as String?,
      edited: raw['edited'] == true,
    );
  }

  /// The line sent with a request: `石井和希 = 이시이 카즈키 (male,
  /// speaks casually)`.
  String get promptLine {
    final notes = <String>[
      if (kind == GlossaryKind.person && gender != GlossaryGender.unknown)
        gender.name,
      if (kind == GlossaryKind.person && speech != null && speech!.isNotEmpty)
        'speaks: $speech',
      if (kind == GlossaryKind.place) 'place',
      if (kind == GlossaryKind.person && !_specific(source))
        'only where it is the name',
    ];
    return notes.isEmpty ? '$source = $target' : '$source = $target (${notes.join(', ')})';
  }
}

/// Who tells the story: a narrator saying 俺 (나), or a narration that
/// follows its hero by name (周は…), where こちら and 自分 are the hero.
enum Narration {
  firstPerson,
  thirdPerson,
  unknown;

  static Narration parse(Object? v) =>
      Narration.values.firstWhere((n) => n.name == v,
          orElse: () => Narration.unknown);
}

class BookGlossary {
  const BookGlossary({
    required this.entries,
    this.complete = false,
    this.narration = Narration.unknown,
    this.hero,
  });

  final List<GlossaryEntry> entries;

  final Narration narration;

  /// The person the narration follows (周), when it is in the third person.
  final String? hero;

  /// The model has sorted and named the candidates; false while only the
  /// book's readings are known.
  final bool complete;

  static const empty = BookGlossary(entries: []);

  bool get isEmpty => entries.isEmpty;

  BookGlossary copyWith({
    List<GlossaryEntry>? entries,
    bool? complete,
    Narration? narration,
    String? hero,
  }) =>
      BookGlossary(
        entries: entries ?? this.entries,
        complete: complete ?? this.complete,
        narration: narration ?? this.narration,
        hero: hero ?? this.hero,
      );

  /// What a request is told about the narration, in its words for Korean.
  String? get narrationNote {
    switch (narration) {
      case Narration.firstPerson:
        return 'The story is told in the first person: the narrator (俺, 僕, '
            '私 in narration) is 나.';
      case Narration.thirdPerson:
        final name = hero == null
            ? null
            : entries
                .where((e) => e.source == hero && e.target.isNotEmpty)
                .map((e) => e.target)
                .firstOrNull;
        if (hero == null || name == null) {
          return 'The story is told in the third person: keep it so, with no '
              '나 in narration (こちら is the one the narration follows, 自分 '
              'is 자신).';
        }
        return 'The story is told in the third person, following $hero '
            '($name): in narration こちら is $name (or $name 쪽) and 自分 is '
            '$name or 자신, never 나.';
      case Narration.unknown:
        return null;
    }
  }

  /// The entries [texts] contain, longest first (石井和希 before 和希), at
  /// most [limit]. A one-kanji entry only when it is a person (周 = 아마네),
  /// marked as a name only: 周 is also "around".
  List<GlossaryEntry> inTexts(Iterable<String> texts, {int limit = 24}) {
    final joined = texts.join('\n');
    final hits = entries
        .where((e) =>
            e.target.isNotEmpty &&
            (_specific(e.source) || e.kind == GlossaryKind.person))
        .where((e) => joined.contains(e.source))
        .toList()
      ..sort((a, b) => b.source.length.compareTo(a.source.length));
    return hits.take(limit).toList();
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'complete': complete,
        'narration': narration.name,
        if (hero != null) 'hero': hero,
        'entries': [for (final e in entries) e.toJson()],
      };

  static BookGlossary fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final list = raw['entries'];
    return BookGlossary(
      complete: raw['complete'] == true,
      narration: Narration.parse(raw['narration']),
      hero: raw['hero'] is String ? raw['hero'] as String : null,
      entries: list is List
          ? list.map(GlossaryEntry.fromJson).whereType<GlossaryEntry>().toList()
          : const [],
    );
  }

  String encode() => jsonEncode(toJson());
  static BookGlossary decode(String text) {
    try {
      return fromJson(jsonDecode(text));
    } catch (_) {
      return empty;
    }
  }
}

bool _specific(String source) =>
    source.runes.length >= 2 || !_kanjiOnly.hasMatch(source);

// ---------------------------------------------------------------------------
// Candidates
// ---------------------------------------------------------------------------

/// A word from the book worth a glossary entry.
class GlossaryCandidate {
  const GlossaryCandidate({
    required this.source,
    required this.count,
    required this.example,
    this.reading,
    this.boyHonorifics = 0,
    this.girlHonorifics = 0,
  });

  final String source;

  /// Times the book calls it 〜くん / 〜君 (a boy), and 〜ちゃん (mostly a
  /// girl): the gender the model guesses from one line is often wrong.
  final int boyHonorifics;
  final int girlHonorifics;
  final String? reading;
  final int count;

  /// A short stretch of the book around it.
  final String example;
}

final _kanjiOnly = RegExp(r'^[一-鿿々]+$');
final _smallKanaForCount = RegExp('[ゃゅょャュョぁぃぅぇぉァィゥェォ]');
final _honorificName = RegExp(
    r'([一-鿿々]{1,4}|[ァ-ヴー]{2,8})(?=さん|くん|君|ちゃん|先輩|先生|様|さま|氏|殿)');
final _katakanaWord = RegExp(r'[ァ-ヴ][ァ-ヴー]{2,9}');

/// Words that stand before an honorific without being anyone's name
/// (彼女さん, お母さん, 天使様).
const _notNames = {
  '彼女', '彼氏', '自分', '皆', '皆様', 'あなた', '貴方', 'お前', '先生', '先輩',
  '後輩', 'お母', 'お父', 'お兄', 'お姉', 'お婆', 'お爺', 'お嬢', '母', '父', '兄',
  '姉', '天使', '神', '王', '女王', '王子', '姫', '店員', '女子', '男子', '生徒',
  '友達', '奥', '旦那', 'お客', '客', '皆々', 'みな', 'お医者', '嬢', '坊', '婆',
  '爺', '娘', '叔', '伯', '様', '諸', '貴', '探偵', '助手', '変態', '刑事', '隣',
  'お隣',
  // Pronouns a character says in katakana (an accent): ワタシ, アナタ.
  'ワタシ', 'アタシ', 'アナタ', 'アンタ', 'ボク', 'オレ', 'キミ', 'オマエ',
  'ワタクシ', 'ワシ',
};

// What follows a name: a particle, punctuation, an honorific. A verb or
// adjective stem given a reading (瞬 まばた of 瞬く, 呟 つぶや) is followed
// by its okurigana instead.
final _afterName = RegExp(
    r'^(?:[はがのをにともへやかよねで、。」』…─！？!?・）\s]|さん|くん|君|ちゃん|先|様|$)');

/// Candidates from [paragraphs] (the book's text) and its furigana
/// [readings]: names given a reading, words before an honorific, and
/// katakana words used again and again. Most frequent first, at most
/// [limit].
List<GlossaryCandidate> glossaryCandidates(
  List<String> paragraphs,
  Map<String, String> readings, {
  int limit = 36,
}) {
  final text = paragraphs.join('\n');
  int count(String word) {
    var n = 0;
    for (var i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + 1)) {
      n++;
    }
    return n;
  }

  final found = <String, (String?, int)>{};
  readings.forEach((base, reading) {
    // One kanji only with a name-like reading (周 あまね, not 鞄 かばん).
    if (base.runes.length < 2 &&
        reading.replaceAll(_smallKanaForCount, '').length < 3) {
      return;
    }
    var n = 0, named = 0;
    for (var i = text.indexOf(base); i >= 0; i = text.indexOf(base, i + 1)) {
      n++;
      if (_afterName.hasMatch(text.substring(i + base.length,
          (i + base.length + 3).clamp(0, text.length)))) {
        named++;
      }
    }
    if (n > 0 && named * 2 < n) return;
    found[base] = (reading, n);
  });
  final honorific = <String, int>{};
  for (final m in _honorificName.allMatches(text)) {
    final w = m.group(1)!;
    honorific[w] = (honorific[w] ?? 0) + 1;
  }
  honorific.forEach((w, n) {
    // One kanji too (唯ちゃん), but only called so again and again.
    if (n >= (w.runes.length >= 2 ? 3 : 4) &&
        !found.containsKey(w) &&
        !_notNames.contains(w)) {
      found[w] = (null, count(w));
    }
  });
  final katakana = <String, int>{};
  for (final m in _katakanaWord.allMatches(text)) {
    final w = m.group(0)!;
    katakana[w] = (katakana[w] ?? 0) + 1;
  }
  katakana.forEach((w, n) {
    if (n >= 5 && !found.containsKey(w) && !_notNames.contains(w)) {
      found[w] = (null, n);
    }
  });

  // A one-kanji word is a name only if someone is called by it: 「周、」,
  // 唯ちゃん (瞳 ひとみ is only ever an eye).
  final spoken = paragraphs.where((p) => p.startsWith('「')).join('\n');
  found.removeWhere((w, _) =>
      w.runes.length == 1 &&
      !RegExp('(?<![一-鿿々])${RegExp.escape(w)}'
              '(?:[、！？!?]|さん|くん|君|ちゃん)')
          .hasMatch(spoken));

  // A shorter candidate inside a longer one counts on its own only where
  // it appears alone (和希 in 石井和希).
  final ranked = found.entries.where((e) => e.value.$2 >= 2).toList()
    ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
  int honorifics(String word, String pattern) =>
      RegExp('${RegExp.escape(word)}(?:$pattern)').allMatches(text).length;
  final picked = [for (final e in ranked.take(limit)) e.key];
  // A family name and a given name written together (藤宮周) are one
  // person: how either is addressed tells both's gender.
  final partners = {
    for (final w in picked)
      w: [
        for (final o in picked)
          if (o != w && (text.contains('$w$o') || text.contains('$o$w'))) o,
      ],
  };
  int addressed(String word, String pattern) =>
      honorifics(word, pattern) +
      partners[word]!.fold(0, (n, o) => n + honorifics(o, pattern));
  return [
    for (final e in ranked.take(limit))
      GlossaryCandidate(
        source: e.key,
        reading: e.value.$1,
        count: e.value.$2,
        example: _exampleOf(paragraphs, e.key),
        boyHonorifics: addressed(e.key, 'くん|君'),
        girlHonorifics: addressed(e.key, 'ちゃん'),
      ),
  ];
}

String _exampleOf(List<String> paragraphs, String word) {
  // What the person says (a line of dialogue the next sentence gives to
  // them: 「…」 / 真昼は小さく笑った): how they talk. A line that names
  // them, saying more than the word (「シエスタ」 alone does not tell a name
  // from 낮잠): how they are talked to. A line of narration with them as
  // the one who acts: what kind of word it is.
  String line(String p) => p.replaceAll('\n', ' ');
  bool short(String p) => p.length <= 80;
  String? says, named, told;
  for (var i = 0; i + 1 < paragraphs.length && says == null; i++) {
    final p = paragraphs[i];
    if (!p.startsWith('「') || !short(p) || p.contains(word)) continue;
    final next = paragraphs[i + 1];
    if (next.startsWith('「')) continue;
    // 「…」 / 真昼は笑った, or 「…」 / と真昼が言う: the next sentence opens
    // with the speaker.
    if (RegExp('^(?:と|そう|、)?${RegExp.escape(word)}[はがも]').hasMatch(next)) {
      says = line(p);
    }
  }
  for (final p in paragraphs) {
    if (p.startsWith('「') &&
        p.contains(word) &&
        short(p) &&
        p.length >= word.length + 10) {
      named = line(p);
      break;
    }
  }
  String snippet(String p, int i) {
    final start = (i - 16).clamp(0, p.length);
    final end = (i + word.length + 22).clamp(0, p.length);
    return line(p.substring(start, end));
  }

  for (final p in paragraphs) {
    if (p.startsWith('「')) continue;
    var i = p.indexOf('$wordは');
    if (i < 0) i = p.indexOf('$wordが');
    if (i >= 0) {
      told = snippet(p, i);
      break;
    }
  }
  if (told == null) {
    for (final p in paragraphs) {
      final i = p.indexOf(word);
      if (i >= 0 && !p.startsWith('「') && p.length >= word.length + 6) {
        told = snippet(p, i);
        break;
      }
    }
  }
  if (says == null && named == null && told == null) {
    for (final p in paragraphs) {
      final i = p.indexOf(word);
      if (i >= 0) return snippet(p, i);
    }
    return '';
  }
  return [
    if (says != null) 'says: $says',
    if (named != null) 'named: $named',
    if (told != null) 'story: $told',
  ].join(' / ');
}

/// Candidates for the EPUB in [bytes] (for an isolate).
List<GlossaryCandidate> epubGlossaryCandidates(Uint8List bytes) =>
    epubSurvey(bytes).candidates;

/// The EPUB in [bytes]: its glossary candidates and how it is narrated
/// (for an isolate).
({List<GlossaryCandidate> candidates, Narration narration, String? hero})
    epubSurvey(Uint8List bytes) {
  final book = EpubPackage.open(bytes);
  if (book == null) {
    return (candidates: const [], narration: Narration.unknown, hero: null);
  }
  final paragraphs = [
    for (final path in book.spine) ...readerParagraphs(book.text(path) ?? ''),
  ];
  final candidates = glossaryCandidates(paragraphs, epubRubyReadings(book));
  final told = bookNarration(paragraphs, [for (final c in candidates) c.source]);
  return (candidates: candidates, narration: told.narration, hero: told.hero);
}

// ---------------------------------------------------------------------------
// The model's part
// ---------------------------------------------------------------------------

/// How many candidates one request takes.
const glossaryRequestSize = 12;

/// One request: sort [candidates] into people, places and terms, give
/// each its Korean form and each person a gender.
String glossaryPrompt(List<GlossaryCandidate> candidates) {
  final b = StringBuffer()
    ..writeln('You are preparing a glossary for translating a Japanese light '
        'novel into Korean.')
    ..writeln('For each numbered entry (a word from the book, its reading if '
        'known, and where it appears) answer exactly one line:')
    ..writeln('[number] Korean | kind | gender | speech')
    ..writeln('- kind: person, place, or term (an ordinary word or thing; '
        'also a nickname, code name or form of address that is an ordinary '
        'word: コウモリ → 박쥐, マーム → 마담). Judge by how the examples use '
        'it: a word that names someone who talks and acts is a person, even '
        'if it is also an ordinary word; a word for a kind of person (ファン, '
        'アイドル, 刑事) is a term')
    ..writeln('- Korean: for a person or a place, the name written by its '
        'Japanese reading in Hangul (石井和希 → 이시이 카즈키, シャーロット → '
        '샬럿); for a term, its natural Korean translation')
    ..writeln('- gender: male or female, from the examples (彼女, how they '
        'talk and are talked to, a girl\'s or boy\'s name); - only for a person '
        'nothing tells, and for places and terms')
    ..writeln('- speech: for a person whose own words appear (after "says:"), '
        'how they talk in a few words: polite or casual, and their tone '
        '(polite, gentle; casual, teasing); otherwise -. A line after '
        '"named:" may be someone else talking to them.')
    ..writeln()
    ..writeln('Entries:');
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    final reading = c.reading == null ? '' : ' (${c.reading})';
    b.writeln('[${i + 1}] ${c.source}$reading — ${c.example}');
  }
  return b.toString().trimRight();
}

final _answerLine = RegExp(r'^\s*\[(\d+)\]\s*(.+)$');
final _hangul = RegExp(r'[가-힣]');
final _foreign = RegExp(r'[぀-ヿ一-鿿]');
final _katakana = RegExp(r'[ァ-ヴ]');
final _katakanaOnly = RegExp(r'^[ァ-ヴー]+$');

/// The entries in the model's answer to [glossaryPrompt]. A person's or
/// place's name keeps the model's Hangul only when it is close to the
/// reading the book gives; otherwise the reading, transliterated, wins.
List<GlossaryEntry> parseGlossaryAnswer(
    String answer, List<GlossaryCandidate> candidates) {
  final out = <GlossaryEntry>[];
  final seen = <int>{};
  for (final line in answer.split('\n')) {
    final m = _answerLine.firstMatch(line);
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    if (n < 1 || n > candidates.length || !seen.add(n)) continue;
    final parts = m.group(2)!.split('|').map((p) => p.trim()).toList();
    if (parts.isEmpty) continue;
    final c = candidates[n - 1];
    var target = parts[0].replaceAll(RegExp(r'[*"“”]'), '').trim();
    final kind = parts.length > 1 ? GlossaryKind.parse(parts[1]) : null;
    var gender = parts.length > 2
        ? GlossaryGender.parse(parts[2])
        : GlossaryGender.unknown;
    // How the book addresses the person outweighs the model's guess.
    if (c.boyHonorifics >= 2 && c.boyHonorifics > c.girlHonorifics) {
      gender = GlossaryGender.male;
    } else if (c.girlHonorifics >= 2 && c.girlHonorifics > c.boyHonorifics) {
      gender = GlossaryGender.female;
    }
    final resolvedKind = kind ?? GlossaryKind.term;
    final speechText = parts.length > 3 ? parts[3].trim() : '';
    final speech = resolvedKind == GlossaryKind.person &&
            RegExp(r'polite|casual|formal|rough|blunt|gentle',
                    caseSensitive: false)
                .hasMatch(speechText)
        ? speechText.toLowerCase()
        : null;
    if (resolvedKind != GlossaryKind.term && c.reading != null) {
      final spelled = kanaToHangul(c.reading!);
      final bare = target.replaceAll(' ', '');
      if (!_hangul.hasMatch(target) ||
          _foreign.hasMatch(target) ||
          !_soundsLike(bare, spelled)) {
        target = spelled;
      }
    }
    if (target.isEmpty || _foreign.hasMatch(target)) continue;
    if (_notNames.contains(c.source)) continue;
    // A term is fixed only where the book reads it its own way (脇役 read
    // モブ); a loanword, a sound word or a word given its usual reading
    // (眼差 まなざ) is left to the translation.
    // A katakana word that is not a name (a loanword: タッパー, リビング)
    // is left to the translation: fixing one form for it turned out wrong
    // as often as right (タッパー → 뚜껑).
    if (resolvedKind != GlossaryKind.person &&
        c.reading == null &&
        _katakanaOnly.hasMatch(c.source)) {
      continue;
    }
    if (resolvedKind == GlossaryKind.term &&
        (c.reading == null || !_katakana.hasMatch(c.reading!))) {
      continue;
    }
    out.add(GlossaryEntry(
      source: c.source,
      target: target,
      reading: c.reading,
      kind: resolvedKind,
      gender: resolvedKind == GlossaryKind.person
          ? gender
          : GlossaryGender.unknown,
      speech: speech,
    ));
  }
  return out;
}

/// Whether the model's [name] is the [spelled] reading, give or take a
/// long vowel or a syllable (후우비 for 후비, not 풍미 for 후비).
bool _soundsLike(String name, String spelled) {
  if ((name.length - spelled.length).abs() > 1) return false;
  final left = spelled.split('');
  var shared = 0;
  for (final ch in name.split('')) {
    if (left.remove(ch)) shared++;
  }
  return shared * 2 >= spelled.length + 1 || shared == spelled.length;
}

/// Full names spelled as one word (天田照人 → 아마다테루히토, from the
/// reading) split after the family name another entry gives (天田 = 아마다):
/// 아마다 테루히토.
///
/// A family name also takes the gender of the one full name it starts
/// (氷高 of 氷高命: female), and none when several people share it.
List<GlossaryEntry> tidyNames(List<GlossaryEntry> entries) {
  final names = {
    for (final e in entries)
      if (e.kind == GlossaryKind.person) e.source: e.target,
  };
  final people = entries.where((e) => e.kind == GlossaryKind.person).toList();
  return [
    for (final e in entries)
      if (e.kind == GlossaryKind.person && !e.edited)
        _familyGender(
            e.target.contains(' ') ? e : _splitFullName(e, names), people)
      else
        e,
  ];
}

GlossaryEntry _familyGender(GlossaryEntry e, List<GlossaryEntry> people) {
  final full = people
      .where((o) => o.source != e.source && o.source.startsWith(e.source))
      .toList();
  if (full.isEmpty) return e;
  final genders = {for (final o in full) o.gender};
  return e.copyWith(
      gender: genders.length == 1 ? genders.first : GlossaryGender.unknown);
}

GlossaryEntry _splitFullName(GlossaryEntry e, Map<String, String> names) {
  for (final MapEntry(key: family, value: hangul) in names.entries) {
    if (family == e.source || !e.source.startsWith(family)) continue;
    if (hangul.contains(' ') || !e.target.startsWith(hangul)) continue;
    final rest = e.target.substring(hangul.length);
    if (rest.isEmpty) continue;
    return e.copyWith(target: '$hangul $rest');
  }
  return e;
}

/// The glossary before the model has looked at it: the book's furigana
/// for words it gives one, as a hint (not yet a fixed form).
BookGlossary readingsGlossary(Map<String, String> readings) => BookGlossary(
      entries: [
        for (final e in readings.entries)
          if (e.key.runes.length >= 2)
            GlossaryEntry(
              source: e.key,
              target: '',
              reading: e.value,
              kind: GlossaryKind.term,
            ),
      ],
    );

/// [fresh] entries over [old] ones, the reader's edits kept as they are
/// (an entry a request failed to bring back stays as it was).
BookGlossary mergeGlossary(BookGlossary old, List<GlossaryEntry> fresh) {
  final merged = <String, GlossaryEntry>{
    for (final e in old.entries) e.source: e,
  };
  for (final e in fresh) {
    if (merged[e.source]?.edited ?? false) continue;
    merged[e.source] = e;
  }
  return old.copyWith(
      entries: tidyNames(merged.values.toList()), complete: true);
}

/// How [paragraphs] narrate: in the first person when the narration says
/// 俺, 僕 or 私 often (more than once in 15 paragraphs), otherwise in the
/// third person. Its hero is the [names] candidate the narration sees
/// things through (周としては, 周にとって, 周自身) clearly more than anyone
/// else's; the heroine may well be named more often.
({Narration narration, String? hero}) bookNarration(
    List<String> paragraphs, Iterable<String> names) {
  final told = paragraphs
      .where((p) => !RegExp(r'^[「『（(“]').hasMatch(p))
      .toList();
  if (told.length < 30) return (narration: Narration.unknown, hero: null);
  final text = told.join('\n');
  final self = RegExp(r'俺|僕|(?<!私立)私(?!立)').allMatches(text).length;
  if (self * 15 > told.length) {
    return (narration: Narration.firstPerson, hero: null);
  }
  String? hero;
  var best = 0, second = 0;
  for (final n in names) {
    final c = RegExp('${RegExp.escape(n)}(?:としては|としても|にとって|自身|の方から)')
        .allMatches(text)
        .length;
    if (c > best) {
      second = best;
      best = c;
      hero = n;
    } else if (c > second) {
      second = c;
    }
  }
  if (best < 5 || best < second * 2) hero = null;
  return (narration: Narration.thirdPerson, hero: hero);
}

// ---------------------------------------------------------------------------
// Kana to Hangul (names)
// ---------------------------------------------------------------------------

const _row = {
  'あ': '아', 'い': '이', 'う': '우', 'え': '에', 'お': '오',
  'か': '카', 'き': '키', 'く': '쿠', 'け': '케', 'こ': '코',
  'が': '가', 'ぎ': '기', 'ぐ': '구', 'げ': '게', 'ご': '고',
  'さ': '사', 'し': '시', 'す': '스', 'せ': '세', 'そ': '소',
  'ざ': '자', 'じ': '지', 'ず': '즈', 'ぜ': '제', 'ぞ': '조',
  'た': '타', 'ち': '치', 'つ': '츠', 'て': '테', 'と': '토',
  'だ': '다', 'ぢ': '지', 'づ': '즈', 'で': '데', 'ど': '도',
  'な': '나', 'に': '니', 'ぬ': '누', 'ね': '네', 'の': '노',
  'は': '하', 'ひ': '히', 'ふ': '후', 'へ': '헤', 'ほ': '호',
  'ば': '바', 'び': '비', 'ぶ': '부', 'べ': '베', 'ぼ': '보',
  'ぱ': '파', 'ぴ': '피', 'ぷ': '푸', 'ぺ': '페', 'ぽ': '포',
  'ま': '마', 'み': '미', 'む': '무', 'め': '메', 'も': '모',
  'や': '야', 'ゆ': '유', 'よ': '요',
  'ら': '라', 'り': '리', 'る': '루', 'れ': '레', 'ろ': '로',
  'わ': '와', 'ゐ': '이', 'ゑ': '에', 'を': '오', 'ゔ': '부',
  'ぁ': '아', 'ぃ': '이', 'ぅ': '우', 'ぇ': '에', 'ぉ': '오',
};

const _youon = {
  'きゃ': '캬', 'きゅ': '큐', 'きょ': '쿄',
  'ぎゃ': '갸', 'ぎゅ': '규', 'ぎょ': '교',
  'しゃ': '샤', 'しゅ': '슈', 'しょ': '쇼',
  'じゃ': '자', 'じゅ': '주', 'じょ': '조',
  'ちゃ': '차', 'ちゅ': '추', 'ちょ': '초',
  'にゃ': '냐', 'にゅ': '뉴', 'にょ': '뇨',
  'ひゃ': '햐', 'ひゅ': '휴', 'ひょ': '효',
  'びゃ': '뱌', 'びゅ': '뷰', 'びょ': '뵤',
  'ぴゃ': '퍄', 'ぴゅ': '퓨', 'ぴょ': '표',
  'みゃ': '먀', 'みゅ': '뮤', 'みょ': '묘',
  'りゃ': '랴', 'りゅ': '류', 'りょ': '료',
  'てぃ': '티', 'でぃ': '디', 'ふぁ': '파', 'ふぃ': '피', 'ふぇ': '페',
  'ふぉ': '포', 'うぃ': '위', 'うぇ': '웨', 'うぉ': '워', 'しぇ': '셰',
  'ちぇ': '체', 'じぇ': '제', 'つぁ': '차',
};

String _hiragana(String s) => String.fromCharCodes(s.runes.map(
    (r) => r >= 0x30A1 && r <= 0x30F6 ? r - 0x60 : r));

/// [syllable] with a final consonant added (ㄴ = 4, ㅅ = 19).
String _withFinal(String syllable, int finalIndex) {
  final code = syllable.codeUnitAt(0);
  if (code < 0xAC00 || code > 0xD7A3 || (code - 0xAC00) % 28 != 0) {
    return syllable;
  }
  return String.fromCharCode(code + finalIndex);
}

/// A name's kana reading in Hangul the way Korean light-novel editions
/// spell names: かずき → 카즈키, しょうた → 쇼타, いっせい → 잇세이,
/// けんた → 켄타. Long vowels after o and u are dropped, as names are
/// usually written.
String kanaToHangul(String kana) {
  final s = _hiragana(kana.trim());
  final out = <String>[];
  String? previousVowelRow;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final pair = i + 1 < s.length ? s.substring(i, i + 2) : null;
    if (pair != null && _youon.containsKey(pair)) {
      out.add(_youon[pair]!);
      previousVowelRow = _vowelOf(pair[1]);
      i++;
      continue;
    }
    if (ch == 'ー') continue;
    if (ch == 'ん') {
      if (out.isNotEmpty) {
        out[out.length - 1] = _withFinal(out.last, 4);
      } else {
        out.add('은');
      }
      previousVowelRow = null;
      continue;
    }
    if (ch == 'っ') {
      if (out.isNotEmpty) out[out.length - 1] = _withFinal(out.last, 19);
      previousVowelRow = null;
      continue;
    }
    // おう, こう, ゆう ... : the second vowel is the long mark of the first.
    if (ch == 'う' &&
        (previousVowelRow == 'o' || previousVowelRow == 'u') &&
        out.isNotEmpty) {
      continue;
    }
    final h = _row[ch];
    if (h == null) {
      if (RegExp(r'\s').hasMatch(ch)) out.add(' ');
      previousVowelRow = null;
      continue;
    }
    out.add(h);
    previousVowelRow = _vowelOf(ch);
  }
  return out.join().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _vowelOf(String kana) {
  const rows = {
    'a': 'あかがさざただなはばぱまやらわぁゃ',
    'i': 'いきぎしじちぢにひびぴみりぃ',
    'u': 'うくぐすずつづぬふぶぷむゆるぅゅ',
    'e': 'えけげせぜてでねへべぺめれぇ',
    'o': 'おこごそぞとどのほぼぽもよろをぉょ',
  };
  for (final e in rows.entries) {
    if (e.value.contains(kana)) return e.key;
  }
  return null;
}
