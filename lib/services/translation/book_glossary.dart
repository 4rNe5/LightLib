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
import 'package:openlib/services/translation/japanese_names.dart';
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
    this.family,
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

  /// The family name this full name starts with (天田 of 天田照人), when
  /// the book shows it is one: the given name is also used alone. Only
  /// then is the Korean written in two words (아마다 테루히토). A short
  /// form of a given name (純 of 純太郎) is not a family name: 준타로.
  /// Empty: two names, cut where [target] has its space, by an engine
  /// that read the whole book (a full name the book never shortens).
  final String? family;

  bool get isName => kind != GlossaryKind.term;

  GlossaryEntry copyWith({
    String? target,
    GlossaryKind? kind,
    GlossaryGender? gender,
    String? speech,
    bool? edited,
    String? Function()? family,
  }) =>
      GlossaryEntry(
        source: source,
        target: target ?? this.target,
        reading: reading,
        kind: kind ?? this.kind,
        gender: gender ?? this.gender,
        speech: speech ?? this.speech,
        edited: edited ?? this.edited,
        family: family == null ? this.family : family(),
      );

  Map<String, Object?> toJson() => {
        'source': source,
        'target': target,
        if (reading != null) 'reading': reading,
        'kind': kind.name,
        'gender': gender.name,
        if (speech != null) 'speech': speech,
        if (edited) 'edited': true,
        if (family != null) 'family': family,
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
      family: raw['family'] is String ? raw['family'] as String : null,
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
    this.version = currentVersion,
  });

  /// How glossaries are made now. One made before (version 1) may hold a
  /// given name cut in two (준 타로), a school spelled by its reading
  /// (에이가코코) and no name written in hiragana: [upgradeGlossary] sets
  /// that right from the book, without the model.
  static const currentVersion = 2;

  /// The version this glossary was made as.
  final int version;

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
    int? version,
  }) =>
      BookGlossary(
        entries: entries ?? this.entries,
        complete: complete ?? this.complete,
        narration: narration ?? this.narration,
        hero: hero ?? this.hero,
        version: version ?? this.version,
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

  /// Every entry a request may be told, the same list in the same order
  /// for the whole book (longest first, as [inTexts]): sent with each
  /// request to an engine that reads long instructions for little, so
  /// that no name is ever out of sight - and so that requests open alike.
  List<GlossaryEntry> forBook({int limit = 160}) {
    final all = entries
        .where((e) =>
            e.target.isNotEmpty &&
            (_specific(e.source) || e.kind == GlossaryKind.person))
        .toList()
      ..sort((a, b) {
        final byLength = b.source.length.compareTo(a.source.length);
        return byLength != 0 ? byLength : a.source.compareTo(b.source);
      });
    return all.take(limit).toList();
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'complete': complete,
        'narration': narration.name,
        if (hero != null) 'hero': hero,
        'entries': [for (final e in entries) e.toJson()],
      };

  static BookGlossary fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final list = raw['entries'];
    return BookGlossary(
      version: raw['version'] is int ? raw['version'] as int : 1,
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
    this.familyLength,
  });

  final String source;

  /// How many of [source]'s characters are a family name (2 of 天田照人),
  /// when the book shows the rest is a given name: it is used alone, or
  /// the first part is how a person is formally addressed (天田さん) and
  /// never a pet name (純くん of 純太郎).
  final int? familyLength;

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

/// A name written in hiragana (しずく) shows only by how it is used: it
/// stands before an honorific, at the start of a word.
final _hiraganaName = RegExp(
    r'(?<![ぁ-ゖ])([ぁ-ゖ]{2,5})(?=さん|くん|君|ちゃん|先輩|先生|様)');

/// Hiragana before an honorific that is no one's name (たくさん, みなさん,
/// お母さん written out).
const _notHiraganaNames = {
  'たく', 'みな', 'みんな', 'おかあ', 'おとう', 'おにい', 'おねえ', 'おじい',
  'おばあ', 'おじ', 'おば', 'かあ', 'とう', 'にい', 'ねえ', 'じい', 'ばあ',
  'あなた', 'おまえ', 'あんた', 'きみ', 'だれ', 'どなた', 'かれ', 'かのじょ',
  'じぶん', 'おきゃく', 'おじょう', 'おく', 'おかみ', 'だんな', 'むすめ',
  'むすこ', 'おいしゃ', 'おまわり', 'その', 'この', 'あの', 'どの', 'した',
  'れた', 'った', 'ない', 'いる', 'ある', 'する', 'なる', 'という', 'こちら',
  'そちら', 'あちら', 'どちら', 'ごくろう', 'おつかれ', 'おせわ', 'ひと',
  'こども', 'あか', 'ぼっ', 'おぼっ', 'いも', 'あね', 'あに', 'はは', 'ちち',
};

/// How one is addressed by family name, or as someone's senior.
const _formalHonorific = 'さん|先生|先輩|様|氏';

/// Katakana words every story uses and no one is named: left to the
/// translation, and out of the way of the names.
const _commonLoanwords = {
  'クラス', 'クラスメイト', 'デート', 'メッセージ', 'ゲーム', 'コーヒー',
  'メニュー', 'ベッド', 'イメージ', 'タイミング', 'スマホ', 'スマートフォン',
  'テーブル', 'カップ', 'カップル', 'ドラマ', 'モデル', 'バイト', 'アルバイト',
  'テスト', 'タイプ', 'プリント', 'スポーツ', 'ホームルーム', 'ルート',
  'ファミレス', 'チーム', 'ボール', 'メンバー', 'プライベート', 'コート',
  'ラーメン', 'シュート', 'カウンター', 'アイコン', 'タクシー', 'ホント',
  'カッコ', 'ポツリ', 'ヒラヒラ', 'ゴールデンウィーク', 'ショッピングモール',
  'サングラス', 'プレイ', 'プレー', 'メール', 'ライン', 'ノート', 'ペン',
  'ドア', 'ソファ', 'ソファー', 'キッチン', 'リビング', 'トイレ', 'シャワー',
  'タオル', 'シャツ', 'スカート', 'ズボン', 'パジャマ', 'コンビニ', 'スーパー',
  'レストラン', 'カフェ', 'ケーキ', 'ジュース', 'パン', 'サラダ', 'カレー',
  'ハンバーグ', 'チョコ', 'チョコレート', 'アイス', 'バス', 'エレベーター',
  'エスカレーター', 'ホテル', 'ビル', 'マンション', 'アパート', 'テレビ',
  'ニュース', 'パソコン', 'カメラ', 'ボタン', 'スイッチ', 'ポケット', 'バッグ',
  'カバン', 'プレゼント', 'パーティー', 'イベント', 'ライブ', 'アイドル',
  'ファン', 'アニメ', 'マンガ', 'ラノベ', 'キャラ', 'キャラクター', 'ヒロイン',
  'ストーリー', 'シーン', 'セリフ', 'レベル', 'スキル', 'ステータス', 'ギルド',
  'パーティ', 'ダンジョン', 'モンスター', 'クエスト', 'アイテム', 'ポーション',
  'ランク', 'スライム', 'ドラゴン', 'ゴブリン', 'エルフ', 'ドワーフ',
  'タイトル', 'ページ', 'サイン', 'ポイント', 'チャンス', 'ピンチ', 'ミス',
  'トラブル', 'ショック', 'ストレス', 'プライド', 'プレッシャー', 'テンション',
  'リズム', 'ペース', 'バランス', 'センス', 'マナー', 'ルール', 'システム',
  'データ', 'グループ', 'ペア', 'リーダー', 'ライバル', 'パートナー', 'コンビ',
  'ママ', 'パパ', 'ベンチ', 'グラウンド', 'プール', 'ジャージ', 'ユニフォーム',
  'チャイム', 'プロ', 'アマ', 'トップ', 'ラスト', 'スタート', 'ゴール', 'アウト',
  'セーフ', 'オーケー', 'オッケー', 'ダメ', 'ムリ', 'バカ', 'アホ', 'ヤバ',
  'ドキドキ', 'ワクワク', 'ニコニコ', 'ニヤニヤ', 'キラキラ', 'フワフワ',
  'イライラ', 'ソワソワ', 'モヤモヤ', 'ジロジロ', 'チラチラ', 'コクリ',
  'ニコリ', 'ニヤリ', 'クスクス', 'クスリ', 'ハッキリ', 'ビックリ', 'ガッカリ',
  'ウットリ', 'スッキリ', 'ゆっくり',
};

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
  int limit = 48,
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
  // A name in hiragana (しずくちゃん): called so again and again, and
  // spoken of like a person (しずくは, しずくの) as often.
  final hiragana = <String, int>{};
  for (final m in _hiraganaName.allMatches(text)) {
    final w = m.group(1)!;
    hiragana[w] = (hiragana[w] ?? 0) + 1;
  }
  hiragana.forEach((w, n) {
    if (n < 3 || found.containsKey(w) || _notHiraganaNames.contains(w)) return;
    final told = RegExp('(?<![ぁ-ゖ])${RegExp.escape(w)}(?:[はがのをにともへ、。！？!?」』…]|\$)',
            multiLine: true)
        .allMatches(text)
        .length;
    if (told >= 3) found[w] = (null, count(w));
  });
  // Katakana words used again and again may be names (シエスタ) or plain
  // loanwords (クラス, デート): the model tells. Those no one is called by
  // come after every name, and only a few of them, so that they never
  // push a name out.
  final katakana = <String, int>{};
  for (final m in _katakanaWord.allMatches(text)) {
    final w = m.group(0)!;
    katakana[w] = (katakana[w] ?? 0) + 1;
  }
  final plain = <String>{};
  katakana.forEach((w, n) {
    if (n >= 5 &&
        !found.containsKey(w) &&
        !_notNames.contains(w) &&
        !_commonLoanwords.contains(w)) {
      found[w] = (null, n);
      plain.add(w);
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
  final frequent = found.entries.where((e) => e.value.$2 >= 2).toList()
    ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
  final names = frequent.where((e) => !plain.contains(e.key)).toList();
  final words = frequent.where((e) => plain.contains(e.key)).toList();
  // Some room is kept for them all the same: a story's people may all
  // have katakana names no one adds さん to.
  final kept = names.take(limit - words.length.clamp(0, 12)).toList();
  final ranked = [
    ...kept,
    ...words.take((limit - kept.length).clamp(0, 24)),
  ]..sort((a, b) => b.value.$2.compareTo(a.value.$2));
  int honorifics(String word, String pattern) =>
      RegExp('${RegExp.escape(word)}(?:$pattern)').allMatches(text).length;
  final picked = [for (final e in ranked) e.key];
  // Where a full name is cut (天田|照人): after a shorter candidate it
  // starts with, when the rest is a name of its own - a candidate, or
  // used alone - or when that first part is how the person is formally
  // addressed and never a pet name (純くん is 純太郎's, not a family).
  int? familyLength(String full) {
    if (!_kanjiOnly.hasMatch(full)) return null;
    for (final first in picked) {
      if (first == full || !full.startsWith(first)) continue;
      final rest = full.substring(first.length);
      if (rest.isEmpty) continue;
      final alone = count(rest) - count(full);
      if (picked.contains(rest) || (rest.runes.length >= 2 && alone >= 2)) {
        return first.length;
      }
      if (honorifics(first, _formalHonorific) >= 2 &&
          honorifics(first, 'くん|君|ちゃん') == 0) {
        return first.length;
      }
    }
    return null;
  }
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
    for (final e in ranked)
      GlossaryCandidate(
        source: e.key,
        reading: e.value.$1,
        count: e.value.$2,
        example: _exampleOf(paragraphs, e.key),
        boyHonorifics: addressed(e.key, 'くん|君'),
        girlHonorifics: addressed(e.key, 'ちゃん'),
        familyLength: familyLength(e.key),
      ),
  ];
}

/// The well-known places of Japan [paragraphs] name ([japanPlaceNames],
/// [japanPlaceReadings]), as entries: no model is asked about them. One
/// that the book calls like a person (千葉さん, 石川先生) is someone's
/// name and left to the candidates.
List<GlossaryEntry> knownPlaces(List<String> paragraphs, {int limit = 40}) {
  final text = paragraphs.join('\n');
  final hits = <(String, String, int)>[];
  void look(String source, String target) {
    var n = 0;
    for (var i = text.indexOf(source); i >= 0; i = text.indexOf(source, i + 1)) {
      n++;
    }
    if (n < 2) return;
    if (RegExp('${RegExp.escape(source)}(?:さん|くん|君|ちゃん|先生|先輩|様)')
        .hasMatch(text)) {
      return;
    }
    // Spoken of as somewhere one is, goes to or comes from - twice.
    if (RegExp('${RegExp.escape(source)}'
                '(?:[にでへ]|から|まで|駅|行き|方面|出身|あたり|の街|の駅|の近く|県|市|区)')
            .allMatches(text)
            .length <
        2) {
      return;
    }
    hits.add((source, target, n));
  }

  japanPlaceNames.forEach(look);
  japanPlaceReadings.forEach((source, reading) {
    if (!japanPlaceNames.containsKey(source)) look(source, kanaToHangul(reading));
  });
  hits.sort((a, b) => b.$3.compareTo(a.$3));
  return [
    for (final h in hits.take(limit))
      GlossaryEntry(
        source: h.$1,
        target: h.$2,
        reading: japanPlaceReadings[h.$1],
        kind: GlossaryKind.place,
      ),
  ];
}

/// A name's Korean form from the book's [reading] of it: the reading in
/// Hangul, a common noun it ends in translated (栄華高校 えいがこうこう →
/// 에이가 고등학교), and a place Korean names its own way as Korean does
/// (東京 → 도쿄).
String spellName(String source, String reading) {
  final known = japanPlaceNames[source];
  if (known != null) return known;
  final cut = splitNameSuffix(source, _hiragana(reading));
  if (cut != null) return '${kanaToHangul(cut.reading)} ${cut.korean}';
  return kanaToHangul(reading);
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

/// What a book's text tells about its names, before any model is asked.
typedef BookSurvey = ({
  List<GlossaryCandidate> candidates,
  List<GlossaryEntry> places,
  Narration narration,
  String? hero,

  /// The book's paragraphs, one a line: for an engine that reads the
  /// whole book ([bookAnalysisChunks]), and to tell which names of an
  /// earlier volume this one has.
  String text,
});

const BookSurvey emptySurvey = (
  candidates: <GlossaryCandidate>[],
  places: <GlossaryEntry>[],
  narration: Narration.unknown,
  hero: null,
  text: '',
);

/// The EPUB in [bytes]: its glossary candidates, the well-known places
/// it names, and how it is narrated (for an isolate).
BookSurvey epubSurvey(Uint8List bytes) {
  final book = EpubPackage.open(bytes);
  if (book == null) return emptySurvey;
  final paragraphs = [
    for (final path in book.spine) ...readerParagraphs(book.text(path) ?? ''),
  ];
  final candidates = glossaryCandidates(paragraphs, epubRubyReadings(book));
  final told = bookNarration(paragraphs, [for (final c in candidates) c.source]);
  final taken = {for (final c in candidates) c.source};
  return (
    candidates: candidates,
    places: [
      for (final p in knownPlaces(paragraphs))
        if (!taken.contains(p.source)) p,
    ],
    narration: told.narration,
    hero: told.hero,
    text: paragraphs.join('\n'),
  );
}

// ---------------------------------------------------------------------------
// The whole book read by the engine (Gemini)
// ---------------------------------------------------------------------------

/// How much of the book one request reads.
const bookAnalysisChunk = 30000;

/// [text] (a book, a paragraph a line) in pieces of about
/// [bookAnalysisChunk] characters, cut between paragraphs; at most [most]
/// (a very long book is read from its start).
List<String> bookAnalysisChunks(String text,
    {int size = bookAnalysisChunk, int most = 8}) {
  final chunks = <String>[];
  final now = StringBuffer();
  for (final line in text.split('\n')) {
    if (now.isNotEmpty && now.length + line.length > size) {
      chunks.add(now.toString());
      now.clear();
      if (chunks.length == most) return chunks;
    }
    now.writeln(line);
  }
  if (now.isNotEmpty) chunks.add(now.toString());
  return chunks;
}

/// What an engine that reads the book itself is asked: every name and
/// special term, as the text writes it.
const bookAnalysisInstructions = """
You are preparing the list of names for translating a Japanese light novel into Korean.
Read this part of the book and list every proper name and every special term the story uses more than once: people (a family name, a given name, a full name and a nickname each as the text writes them), places, schools and organisations, named items, skills and spells. Do not list ordinary words, sound words or everyday loanwords.
For each one give:
- src: exactly as it is written in the text.
- reading: how it is read, in hiragana (for a word written in katakana, the katakana itself). Read a name the way the text's own furigana or the story shows; where nothing shows it, the most usual reading.
- kind: person, nickname, place, organisation, item, skill or term.
- ko: the Korean. A person's or place's name by its reading in Hangul (石井和希 → 이시이 카즈키, 風宮 → 카자미야), without long vowels (ゆうな → 유나); a common noun at the end of a name translated (栄華高校 → 에이가 고등학교, 桜駅 → 사쿠라 역); a foreign name as Korean writes it (シャーロット → 샬럿); an item, skill, spell or term by its natural Korean.
- gender: male or female for a person the text shows to be one, otherwise -.
- speech: for a person who speaks, polite or casual and their tone in two or three words (polite, gentle); otherwise -.""";

const bookAnalysisSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'entries': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'src': {'type': 'string'},
          'reading': {'type': 'string'},
          'kind': {'type': 'string'},
          'ko': {'type': 'string'},
          'gender': {'type': 'string'},
          'speech': {'type': 'string'},
        },
        'required': ['src', 'kind', 'ko'],
      },
    },
  },
  'required': ['entries'],
};

final _japanese = RegExp(r'[぀-ヿ一-鿿々]');

/// The entries in an engine's answers to [bookAnalysisInstructions]
/// ([answers]: one JSON text per part of the book), checked against the
/// book ([survey]): a word the text does not have twice is not kept, and
/// a name the book itself spells out - by furigana, or in hiragana - is
/// written as the book has it, whatever the engine answered.
List<GlossaryEntry> parseBookAnalysis(
    Iterable<String> answers, BookSurvey survey) {
  final text = survey.text;
  final candidates = {for (final c in survey.candidates) c.source: c};
  int count(String word) {
    var n = 0;
    for (var i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + 1)) {
      n++;
    }
    return n;
  }

  final out = <String, GlossaryEntry>{};
  // Full names the engine wrote in two words.
  final cut = <String>{};
  for (final answer in answers) {
    final Object? decoded;
    try {
      decoded = jsonDecode(answer);
    } catch (_) {
      continue;
    }
    final list = decoded is Map ? decoded['entries'] : null;
    if (list is! List) continue;
    for (final raw in list) {
      if (raw is! Map) continue;
      final src = '${raw['src'] ?? ''}'.trim();
      if (src.isEmpty || src.runes.length > 12 || out.containsKey(src)) {
        continue;
      }
      if (!_japanese.hasMatch(src) ||
          _notNames.contains(src) ||
          _notHiraganaNames.contains(src) ||
          _commonLoanwords.contains(src)) {
        continue;
      }
      // 純くん, 玲子さん: the name is listed on its own, and how くん is
      // said in Korean is the translation's to say, not a name's.
      final addressed = _addressedForm.firstMatch(src);
      if (addressed != null && addressed.start > 0) continue;
      final c = candidates[src];
      final kindText = '${raw['kind'] ?? ''}'.trim().toLowerCase();
      final ko = '${raw['ko'] ?? ''}'.replaceAll(RegExp(r'[*"“”]'), '').trim();
      var kind = kindText.startsWith('person') ||
              kindText.startsWith('nick') ||
              (c != null && _addressedAsPerson(c, ko))
          ? GlossaryKind.person
          : kindText.startsWith('place') || kindText.startsWith('org')
              ? GlossaryKind.place
              : GlossaryKind.term;
      // One kanji is a name only where the book's own use says so.
      if (src.runes.length == 1 && (kind != GlossaryKind.person || c == null)) {
        continue;
      }
      // An everyday word in katakana is the translation's to word.
      if (kind == GlossaryKind.term &&
          kindText.startsWith('term') &&
          _katakanaOnly.hasMatch(src)) {
        continue;
      }
      if (count(src) < 2) continue;
      final reading = '${raw['reading'] ?? ''}'.trim();
      final usable =
          ko.isNotEmpty && _hangul.hasMatch(ko) && !_foreign.hasMatch(ko);
      String? target;
      if (kind != GlossaryKind.term) {
        final written = c == null ? null : _nameFromBook(c);
        if (written != null) {
          target = written;
        } else if (_hiraganaOnly.hasMatch(src)) {
          target = kanaToHangul(src);
        } else if (_hiraganaOnly.hasMatch(reading) &&
            !_katakana.hasMatch(src)) {
          // The engine's own reading, written the one way names are
          // written here: always for a person (a name is its sound,
          // whatever Korean came with it), otherwise where its Korean is
          // that sound too. Where that is a translation (宿直室 → 숙직실,
          // not 슈쿠초쿠시츠; a nickname that is an ordinary word), its
          // Korean stands - a place's as a term's, it is no name.
          final spelled = spellName(src, reading);
          final bare = ko.replaceAll(' ', '');
          // (A school's or a station's name is its first part: 栄華 of
          // 栄華高校, whatever word the engine has for 高校.)
          final ending = splitNameSuffix(src, reading);
          final alike = ending == null
              ? _soundsLike(bare, spelled.replaceAll(' ', ''))
              : _startsLike(bare, kanaToHangul(ending.reading));
          if (!usable || alike || kindText.startsWith('person')) {
            target = spelled;
          } else if (kind == GlossaryKind.place) {
            kind = GlossaryKind.term;
          }
        }
        // Family and given name, cut where the engine cut them.
        if (target != null &&
            RegExp(r'^\S+ \S+$').hasMatch(ko) &&
            ko.replaceAll(' ', '') == target.replaceAll(' ', '')) {
          target = ko;
          if (kindText.startsWith('person') && src.runes.length >= 4) {
            cut.add(src);
          }
        }
      }
      target ??= ko;
      if (target.isEmpty || !_hangul.hasMatch(target) || _foreign.hasMatch(target)) {
        continue;
      }
      var gender = GlossaryGender.parse('${raw['gender'] ?? ''}');
      if (c != null) {
        if (c.boyHonorifics >= 2 && c.boyHonorifics > c.girlHonorifics) {
          gender = GlossaryGender.male;
        } else if (c.girlHonorifics >= 2 &&
            c.girlHonorifics > c.boyHonorifics) {
          gender = GlossaryGender.female;
        }
      }
      final speechText = '${raw['speech'] ?? ''}'.trim();
      out[src] = GlossaryEntry(
        source: src,
        target: target,
        reading: c?.reading ??
            (_hiraganaOnly.hasMatch(reading) && src != reading ? reading : null),
        kind: kind,
        gender: kind == GlossaryKind.person ? gender : GlossaryGender.unknown,
        speech: kind == GlossaryKind.person &&
                RegExp(r'polite|casual|formal|rough|blunt|gentle',
                        caseSensitive: false)
                    .hasMatch(speechText)
            ? speechText.toLowerCase()
            : null,
        family: c == null ? null : _familyOf(c),
      );
    }
  }
  // Which full names are two names: one that starts with another name
  // of the list and goes on with a name used by itself (神坂 + しずく),
  // or, for a name the book never shortens, where the engine cut it.
  // 純太郎 after 純 is neither.
  final people = {
    for (final e in out.values)
      if (e.kind == GlossaryKind.person) e.source: e,
  };
  for (final e in people.values) {
    if (e.family != null) continue;
    String? family;
    final bare = e.target.replaceAll(' ', '');
    for (var k = e.source.length - 1; k >= 1 && family == null; k--) {
      final first = people[e.source.substring(0, k)];
      final rest = e.source.substring(k);
      if (first == null) continue;
      final head = first.target.replaceAll(' ', '');
      if (!bare.startsWith(head) || bare.length == head.length) continue;
      if (people.containsKey(rest) ||
          candidates.containsKey(rest) ||
          (rest.runes.length >= 2 && count(rest) - count(e.source) >= 2)) {
        family = first.source;
      }
    }
    family ??= cut.contains(e.source) ? '' : null;
    if (family != null) out[e.source] = e.copyWith(family: () => family);
  }
  return out.values.toList();
}

/// Whether [korean] opens with the sound [spelled], give or take a
/// syllable.
bool _startsLike(String korean, String spelled) {
  for (final n in [spelled.length, spelled.length - 1, spelled.length + 1]) {
    if (n >= 1 &&
        n <= korean.length &&
        _soundsLike(korean.substring(0, n), spelled)) {
      return true;
    }
  }
  return false;
}

/// A name with how it is addressed after it (純くん, 玲子さん, 立川先生).
final _addressedForm = RegExp(
    r'(くん|君|ちゃん|さん|様|さま|先輩|せんぱい|センパイ|先生|氏|殿|たん)$');

/// The candidates an engine is still asked about after it read the book
/// ([read]: what the reading named; empty when it did not answer): those
/// it left unnamed - without the words in katakana nobody is addressed
/// by, which it read in their place and did not take for names (イルカ
/// of a dolphin show; asked one line at a time, a model calls it someone).
List<GlossaryCandidate> unnamedCandidates(
    BookSurvey survey, Iterable<GlossaryEntry> read) {
  final named = {for (final e in read) e.source};
  return [
    for (final c in survey.candidates)
      if (!named.contains(c.source) &&
          !(named.isNotEmpty &&
              c.reading == null &&
              c.boyHonorifics + c.girlHonorifics == 0 &&
              _katakanaOnly.hasMatch(c.source)))
        c,
  ];
}

/// [glossary] with what earlier volumes of the series settled ([earlier],
/// their glossaries): a name this book has that it has no entry for is
/// taken over, and so is the way a name is written where the earlier
/// volume knew better - the reader set it, or that book gave its reading
/// and this one does not (風宮 without furigana in volume 1, かざみや in
/// volume 2).
BookGlossary inheritSeries(
    BookGlossary glossary, Iterable<BookGlossary> earlier, String text) {
  final entries = {for (final e in glossary.entries) e.source: e};
  var changed = false;
  for (final other in earlier) {
    for (final e in other.entries) {
      if (e.target.isEmpty || !e.isName || !text.contains(e.source)) continue;
      final mine = entries[e.source];
      if (mine == null) {
        entries[e.source] = e.copyWith(edited: false);
        changed = true;
        continue;
      }
      if (mine.edited || mine.target == e.target) continue;
      final theirsKnows = e.edited || e.reading != null;
      final mineKnows = mine.reading != null;
      if (theirsKnows && !mineKnows) {
        entries[e.source] = mine.copyWith(target: e.target);
        changed = true;
      }
    }
  }
  return changed
      ? glossary.copyWith(entries: tidyNames(entries.values.toList()))
      : glossary;
}

// ---------------------------------------------------------------------------
// The model's part
// ---------------------------------------------------------------------------

/// How many candidates one request takes.
const glossaryRequestSize = 12;

/// The instructions every glossary request opens with.
String glossaryPromptHead() {
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
    ..writeln();
  return b.toString().trimRight();
}

/// One request: sort [candidates] into people, places and terms, give
/// each its Korean form and each person a gender. Opens with
/// [glossaryPromptHead], the same for every request.
String glossaryPrompt(List<GlossaryCandidate> candidates) {
  final b = StringBuffer(glossaryPromptHead())
    ..writeln()
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
    // So does how it is addressed: しずく is "a drop" to the model, and
    // the girl everyone calls しずくちゃん to the book.
    final resolvedKind =
        (kind ?? GlossaryKind.term) == GlossaryKind.term &&
                _addressedAsPerson(c, target)
            ? GlossaryKind.person
            : kind ?? GlossaryKind.term;
    final speechText = parts.length > 3 ? parts[3].trim() : '';
    final speech = resolvedKind == GlossaryKind.person &&
            RegExp(r'polite|casual|formal|rough|blunt|gentle',
                    caseSensitive: false)
                .hasMatch(speechText)
        ? speechText.toLowerCase()
        : null;
    if (resolvedKind != GlossaryKind.term) {
      final written = _nameFromBook(c);
      if (written != null) {
        // The book says how it is read: that, written the one way names
        // are written here, and not the model's own spelling of it
        // (유우나 for ゆうな, 에이카 for えいが). Where the model spells
        // it the same, the space it put between family and given name
        // comes along ([tidyNames] keeps it only where the book shows
        // two names).
        if (target.replaceAll(' ', '') != written.replaceAll(' ', '')) {
          target = written;
        }
      } else if (c.reading != null) {
        // A reading in katakana is a foreign word (聖剣 エクスカリバー):
        // the model's Korean for it, unless it is far from the reading.
        final spelled = spellName(c.source, c.reading!);
        final bare = target.replaceAll(' ', '');
        if (!_hangul.hasMatch(target) ||
            _foreign.hasMatch(target) ||
            !_soundsLike(bare, spelled.replaceAll(' ', ''))) {
          target = spelled;
        }
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
      family: _familyOf(c),
    ));
  }
  return out;
}

final _hiraganaOnly = RegExp(r'^[ぁ-ゖー]+$');

/// The Korean of a name the book itself spells out: one it gives a
/// hiragana reading (結奈 ゆな), or writes in hiragana (しずく). Null for
/// a name only the model can put in Korean (凜 without a reading, a
/// katakana name such as シャーロット).
String? _nameFromBook(GlossaryCandidate c) {
  final reading = c.reading;
  if (reading != null && _hiraganaOnly.hasMatch(reading)) {
    return spellName(c.source, reading);
  }
  if (reading == null && _hiraganaOnly.hasMatch(c.source)) {
    return kanaToHangul(c.source);
  }
  return null;
}

/// Whether the book shows [c] to be someone, whatever kind of word a
/// model took it for: it is written in hiragana (which only a word the
/// book calls 〜くん / 〜ちゃん is a candidate for), or it is so called
/// and [korean] - the model's word for it - is its sound and not a
/// translation (아키라 for アキラ, not 밝음).
bool _addressedAsPerson(GlossaryCandidate c, String korean) {
  if (c.reading == null && _hiraganaOnly.hasMatch(c.source)) return true;
  if (c.boyHonorifics + c.girlHonorifics < 2) return false;
  final spelled = _nameFromBook(c) ??
      (_katakanaOnly.hasMatch(c.source) ? kanaToHangul(c.source) : null);
  return spelled != null &&
      _soundsLike(korean.replaceAll(' ', ''), spelled.replaceAll(' ', ''));
}

/// The names [survey]'s book writes in hiragana (a word in hiragana is
/// a candidate only where the book calls it 〜くん / 〜ちゃん), written
/// as the book has them: there whether or not a model answers about
/// them.
List<GlossaryEntry> hiraganaNames(BookSurvey survey) => [
      for (final c in survey.candidates)
        if (c.reading == null && _hiraganaOnly.hasMatch(c.source))
          GlossaryEntry(
            source: c.source,
            target: kanaToHangul(c.source),
            gender: c.boyHonorifics >= 2 && c.boyHonorifics > c.girlHonorifics
                ? GlossaryGender.male
                : c.girlHonorifics >= 2 && c.girlHonorifics > c.boyHonorifics
                    ? GlossaryGender.female
                    : GlossaryGender.unknown,
          ),
    ];

String? _familyOf(GlossaryCandidate c) => c.familyLength == null
    ? null
    : c.source.substring(0, c.familyLength!.clamp(0, c.source.length));

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

/// A person's name in Korean is one word, or two where the book shows a
/// family name and a given name ([GlossaryEntry.family]): 天田照人 →
/// 아마다 테루히토, after the family name another entry gives (天田 =
/// 아마다) or where the model put the space. Without that it is never
/// cut: 純 is 純太郎's short form, not his family, and 준타로 stays whole
/// whatever the model wrote.
///
/// A family name also takes the gender of the one full name it starts
/// (氷高 of 氷高命: female), and none when several people share it.
List<GlossaryEntry> tidyNames(List<GlossaryEntry> entries) {
  final names = {
    for (final e in entries)
      if (e.kind == GlossaryKind.person)
        e.source: e.target.replaceAll(' ', ''),
  };
  final people = entries.where((e) => e.kind == GlossaryKind.person).toList();
  return [
    for (final e in entries)
      if (e.kind == GlossaryKind.person && !e.edited)
        _familyGender(_spaced(e, names), people)
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

GlossaryEntry _spaced(GlossaryEntry e, Map<String, String> names) {
  final bare = e.target.replaceAll(' ', '');
  final family = e.family;
  if (family == null || bare.isEmpty) return e.copyWith(target: bare);
  final hangul = names[family];
  if (hangul != null &&
      hangul.isNotEmpty &&
      bare.startsWith(hangul) &&
      bare.length > hangul.length) {
    return e.copyWith(target: '$hangul ${bare.substring(hangul.length)}');
  }
  // No entry for the family name: the model's own cut, if it made one.
  final parts = e.target.trim().split(RegExp(r'\s+'));
  return e.copyWith(target: parts.length == 2 ? parts.join(' ') : bare);
}

/// A glossary made before [BookGlossary.currentVersion], set right from
/// what the book's text tells ([survey]) - no model is asked: names cut
/// where the book shows no family name are joined again, names the book
/// gives a reading are spelled from it (a school's last word translated),
/// names written in hiragana and well-known places are added. What the
/// reader changed stays as it is.
BookGlossary upgradeGlossary(BookGlossary old, BookSurvey survey) {
  final bySource = {for (final c in survey.candidates) c.source: c};
  final entries = <String, GlossaryEntry>{};
  for (final e in old.entries) {
    final c = bySource[e.source];
    if (e.edited || c == null || e.target.isEmpty) {
      entries[e.source] = e;
      continue;
    }
    final written = e.isName ? _nameFromBook(c) : null;
    entries[e.source] = e.copyWith(
      target: written ?? e.target,
      family: () => _familyOf(c),
    );
  }
  for (final name in hiraganaNames(survey)) {
    entries.putIfAbsent(name.source, () => name);
  }
  for (final place in survey.places) {
    entries.putIfAbsent(place.source, () => place);
  }
  return old.copyWith(
    entries: tidyNames(entries.values.toList()),
    version: BookGlossary.currentVersion,
  );
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
      entries: tidyNames(merged.values.toList()),
      complete: true,
      version: BookGlossary.currentVersion);
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
