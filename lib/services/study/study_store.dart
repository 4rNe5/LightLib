// The study record: the word book (cards scheduled for review the way
// Anki does), the answers the translation engine gave for words and
// sentences (asked once), and what was studied each day. Kept as JSON in
// a hidden folder next to the books, like translations, so it moves with
// the book folder.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:openlib/services/database.dart';

/// How a card was answered.
enum ReviewGrade { again, hard, good, easy }

@immutable
class StudyCard {
  const StudyCard({
    required this.id,
    required this.word,
    this.reading = '',
    this.meaning = '',
    this.sentence = '',
    this.sentenceMeaning = '',
    this.book = '',
    this.level = 0,
    required this.added,
    required this.due,
    this.interval = 0,
    this.ease = 2.5,
    this.step = 0,
    this.reps = 0,
    this.lapses = 0,
  });

  final String id;
  final String word;
  final String reading;
  final String meaning;
  final String sentence;
  final String sentenceMeaning;

  /// The book it was met in (its title).
  final String book;
  final int level;
  final DateTime added;
  final DateTime due;

  /// Days between reviews; 0 while being learnt.
  final double interval;
  final double ease;

  /// The learning step (0, 1) while [interval] is 0.
  final int step;
  final int reps;
  final int lapses;

  bool get isNew => reps == 0;
  bool get learning => interval == 0;
  bool isDue(DateTime now) => !due.isAfter(now);

  static String idFor(String word, String reading) => '$word\t$reading';

  StudyCard copyWith({
    String? meaning,
    String? sentence,
    String? sentenceMeaning,
    DateTime? due,
    double? interval,
    double? ease,
    int? step,
    int? reps,
    int? lapses,
  }) =>
      StudyCard(
        id: id,
        word: word,
        reading: reading,
        meaning: meaning ?? this.meaning,
        sentence: sentence ?? this.sentence,
        sentenceMeaning: sentenceMeaning ?? this.sentenceMeaning,
        book: book,
        level: level,
        added: added,
        due: due ?? this.due,
        interval: interval ?? this.interval,
        ease: ease ?? this.ease,
        step: step ?? this.step,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
      );

  Map<String, Object> toJson() => {
        'word': word,
        'reading': reading,
        'meaning': meaning,
        'sentence': sentence,
        'sentenceMeaning': sentenceMeaning,
        'book': book,
        'level': level,
        'added': added.millisecondsSinceEpoch,
        'due': due.millisecondsSinceEpoch,
        'interval': interval,
        'ease': ease,
        'step': step,
        'reps': reps,
        'lapses': lapses,
      };

  factory StudyCard.fromJson(Map<String, dynamic> j) {
    final word = '${j['word'] ?? ''}';
    final reading = '${j['reading'] ?? ''}';
    DateTime at(Object? v) =>
        DateTime.fromMillisecondsSinceEpoch((v as num?)?.toInt() ?? 0);
    return StudyCard(
      id: idFor(word, reading),
      word: word,
      reading: reading,
      meaning: '${j['meaning'] ?? ''}',
      sentence: '${j['sentence'] ?? ''}',
      sentenceMeaning: '${j['sentenceMeaning'] ?? ''}',
      book: '${j['book'] ?? ''}',
      level: (j['level'] as num?)?.toInt() ?? 0,
      added: at(j['added']),
      due: at(j['due']),
      interval: (j['interval'] as num?)?.toDouble() ?? 0,
      ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
      step: (j['step'] as num?)?.toInt() ?? 0,
      reps: (j['reps'] as num?)?.toInt() ?? 0,
      lapses: (j['lapses'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The next review of [card] answered [grade] at [now]: learning steps of
/// 1 and 10 minutes, then days that grow by the card's ease (SM-2, as
/// Anki schedules).
StudyCard schedule(StudyCard card, ReviewGrade grade, DateTime now) {
  Duration minutes(int m) => Duration(minutes: m);
  Duration days(double d) => Duration(minutes: (d * 24 * 60).round());
  final reps = card.reps + 1;
  if (card.learning) {
    switch (grade) {
      case ReviewGrade.again:
        return card.copyWith(step: 0, reps: reps, due: now.add(minutes(1)));
      case ReviewGrade.hard:
        return card.copyWith(
            reps: reps, due: now.add(minutes(card.step == 0 ? 6 : 10)));
      case ReviewGrade.good:
        if (card.step == 0) {
          return card.copyWith(step: 1, reps: reps, due: now.add(minutes(10)));
        }
        return card.copyWith(
            interval: 1, step: 0, reps: reps, due: now.add(days(1)));
      case ReviewGrade.easy:
        return card.copyWith(
            interval: 4, step: 0, reps: reps, due: now.add(days(4)));
    }
  }
  switch (grade) {
    case ReviewGrade.again:
      return card.copyWith(
        interval: 0,
        step: 1,
        reps: reps,
        lapses: card.lapses + 1,
        ease: math.max(1.3, card.ease - 0.2),
        due: now.add(minutes(10)),
      );
    case ReviewGrade.hard:
      final next = math.max(1.0, card.interval * 1.2);
      return card.copyWith(
          interval: next,
          reps: reps,
          ease: math.max(1.3, card.ease - 0.15),
          due: now.add(days(next)));
    case ReviewGrade.good:
      final next = math.max(card.interval + 1, card.interval * card.ease);
      return card.copyWith(interval: next, reps: reps, due: now.add(days(next)));
    case ReviewGrade.easy:
      final next = math.max(card.interval + 2, card.interval * card.ease * 1.3);
      return card.copyWith(
          interval: next,
          reps: reps,
          ease: card.ease + 0.15,
          due: now.add(days(next)));
  }
}

/// What a day's study came to.
@immutable
class StudyDay {
  const StudyDay({
    this.looked = 0,
    this.explained = 0,
    this.added = 0,
    this.reviewed = 0,
    this.chars = 0,
  });

  /// Words looked up.
  final int looked;

  /// Sentences explained.
  final int explained;

  /// Words added to the word book.
  final int added;

  /// Cards reviewed.
  final int reviewed;

  /// Characters read in the original.
  final int chars;

  bool get active => looked + explained + added + reviewed + chars > 0;

  StudyDay plus(StudyDay o) => StudyDay(
        looked: looked + o.looked,
        explained: explained + o.explained,
        added: added + o.added,
        reviewed: reviewed + o.reviewed,
        chars: chars + o.chars,
      );

  Map<String, int> toJson() => {
        if (looked > 0) 'looked': looked,
        if (explained > 0) 'explained': explained,
        if (added > 0) 'added': added,
        if (reviewed > 0) 'reviewed': reviewed,
        if (chars > 0) 'chars': chars,
      };

  factory StudyDay.fromJson(Map<String, dynamic> j) {
    int v(String k) => (j[k] as num?)?.toInt() ?? 0;
    return StudyDay(
      looked: v('looked'),
      explained: v('explained'),
      added: v('added'),
      reviewed: v('reviewed'),
      chars: v('chars'),
    );
  }
}

String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}'
    '-${t.day.toString().padLeft(2, '0')}';

class StudyStore extends ChangeNotifier {
  StudyStore({this.directory});

  static final StudyStore instance = StudyStore();

  /// Where the files are (replaceable in tests); by default `.study/`
  /// next to the books.
  Future<Directory> Function()? directory;

  /// The clock (replaceable in tests).
  DateTime Function() now = DateTime.now;

  final Map<String, StudyCard> _cards = {};
  final Map<String, Object?> _answers = {};
  final Map<String, StudyDay> _days = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  Directory? _dir;

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final dir = directory != null
        ? await directory!()
        : Directory(p.join(
            '${await MyLibraryDb.instance.getPreference('bookStorageDirectory')}',
            '.study'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final dir = await _directory();
      Future<dynamic> read(String name) async {
        final f = File(p.join(dir.path, name));
        if (!await f.exists()) return null;
        try {
          return jsonDecode(await f.readAsString());
        } catch (_) {
          return null;
        }
      }

      final words = await read('words.json');
      if (words is List) {
        for (final w in words) {
          if (w is! Map) continue;
          final card = StudyCard.fromJson(Map<String, dynamic>.from(w));
          if (card.word.isNotEmpty) _cards[card.id] = card;
        }
      }
      final answers = await read('answers.json');
      if (answers is Map) _answers.addAll(Map<String, Object?>.from(answers));
      final days = await read('days.json');
      if (days is Map) {
        for (final MapEntry(:key, :value) in days.entries) {
          if (value is Map) {
            _days['$key'] = StudyDay.fromJson(Map<String, dynamic>.from(value));
          }
        }
      }
    } catch (_) {
      // No folder yet: an empty record.
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Cards
  // ------------------------------------------------------------------

  List<StudyCard> get cards =>
      _cards.values.toList()..sort((a, b) => b.added.compareTo(a.added));

  bool has(String word, String reading) =>
      _cards.containsKey(StudyCard.idFor(word, reading));

  StudyCard? card(String word, String reading) =>
      _cards[StudyCard.idFor(word, reading)];

  /// Cards to review now: those due longest ago first, then at most
  /// [newLimit] new ones, oldest first.
  List<StudyCard> due({int newLimit = 20}) {
    final t = now();
    final review = <StudyCard>[];
    final fresh = <StudyCard>[];
    for (final c in _cards.values) {
      if (!c.isDue(t)) continue;
      (c.isNew ? fresh : review).add(c);
    }
    review.sort((a, b) => a.due.compareTo(b.due));
    fresh.sort((a, b) => a.added.compareTo(b.added));
    return [...review, ...fresh.take(newLimit)];
  }

  int get dueCount => due().length;

  /// Adds a word (or updates its meaning and sentence).
  Future<StudyCard> add({
    required String word,
    String reading = '',
    String meaning = '',
    String sentence = '',
    String sentenceMeaning = '',
    String book = '',
    int level = 0,
  }) async {
    await load();
    final id = StudyCard.idFor(word, reading);
    final old = _cards[id];
    final t = now();
    final card = old?.copyWith(
          meaning: meaning.isEmpty ? null : meaning,
          sentence: sentence.isEmpty ? null : sentence,
          sentenceMeaning: sentenceMeaning.isEmpty ? null : sentenceMeaning,
        ) ??
        StudyCard(
          id: id,
          word: word,
          reading: reading,
          meaning: meaning,
          sentence: sentence,
          sentenceMeaning: sentenceMeaning,
          book: book,
          level: level,
          added: t,
          due: t,
        );
    _cards[id] = card;
    if (old == null) _count(const StudyDay(added: 1));
    _changed();
    return card;
  }

  Future<void> remove(String id) async {
    await load();
    if (_cards.remove(id) != null) _changed();
  }

  Future<StudyCard?> review(String id, ReviewGrade grade) async {
    await load();
    final card = _cards[id];
    if (card == null) return null;
    final next = schedule(card, grade, now());
    _cards[id] = next;
    _count(const StudyDay(reviewed: 1));
    _changed();
    return next;
  }

  // ------------------------------------------------------------------
  // Answers and days
  // ------------------------------------------------------------------

  Object? answer(String key) => _answers[key];

  void keepAnswer(String key, Object value) {
    _answers[key] = value;
    // A bounded cache: the oldest answers go first.
    while (_answers.length > 4000) {
      _answers.remove(_answers.keys.first);
    }
    _changed(notify: false);
  }

  void count(StudyDay day) {
    _count(day);
    _changed();
  }

  void _count(StudyDay day) {
    final key = dayKey(now());
    _days[key] = (_days[key] ?? const StudyDay()).plus(day);
  }

  StudyDay dayAt(DateTime t) => _days[dayKey(t)] ?? const StudyDay();

  StudyDay get total =>
      _days.values.fold(const StudyDay(), (a, b) => a.plus(b));

  /// Days in a row with any study, up to today (or yesterday, when today
  /// has none yet).
  int get streak {
    var t = now();
    if (!dayAt(t).active) t = t.subtract(const Duration(days: 1));
    var n = 0;
    while (dayAt(t).active) {
      n++;
      t = t.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// The last [count] days, oldest first.
  List<(DateTime, StudyDay)> recent(int count) {
    final t = now();
    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final d = DateTime(t.year, t.month, t.day - i);
          return (d, dayAt(d));
        }(),
    ];
  }

  // ------------------------------------------------------------------
  // Saving
  // ------------------------------------------------------------------

  void _changed({bool notify = true}) {
    if (notify) notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => save());
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    try {
      final dir = await _directory();
      Future<void> write(String name, Object data) async {
        final f = File(p.join(dir.path, name));
        final temp = File('${f.path}.tmp');
        await temp.writeAsString(jsonEncode(data), flush: true);
        await temp.rename(f.path);
      }

      await write('words.json', [for (final c in cards) c.toJson()]);
      await write('answers.json', _answers);
      await write('days.json',
          {for (final MapEntry(:key, :value) in _days.entries) key: value.toJson()});
    } catch (_) {
      // Unwritable folder: kept in memory for this session.
    }
  }

  @visibleForTesting
  void debugReset() {
    _cards.clear();
    _answers.clear();
    _days.clear();
    _loading = null;
    _dir = null;
    _saveTimer?.cancel();
  }
}

/// The word book as a tab-separated file Anki imports (File > Import):
/// word, reading, meaning, sentence, sentence meaning, book, tags.
String ankiExport(List<StudyCard> cards) {
  String field(String s) => s
      .replaceAll('\t', ' ')
      .replaceAll(RegExp(r'\r?\n'), '<br>')
      .trim();
  final out = StringBuffer()
    ..writeln('#separator:tab')
    ..writeln('#html:true')
    ..writeln('#tags column:7')
    ..writeln(
        '#columns:Word\tReading\tMeaning\tSentence\tSentence meaning\tBook\tTags');
  for (final c in cards) {
    final tags = [
      'LightLib',
      if (c.level > 0) 'JLPT_N${c.level}',
    ].join(' ');
    out.writeln([
      field(c.word),
      field(c.reading),
      field(c.meaning),
      field(c.sentence),
      field(c.sentenceMeaning),
      field(c.book),
      tags,
    ].join('\t'));
  }
  return out.toString();
}
