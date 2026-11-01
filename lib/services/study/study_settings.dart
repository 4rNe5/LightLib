// The reader's study settings: how translations show next to the
// original, furigana, the reader's JLPT level, and looking words up with
// a tap. Kept as one preference.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/database.dart';

/// How a translation shows: in place of the original, under it, or under
/// it hidden until tapped.
enum TranslationLayout {
  replace,
  below,
  hidden;

  static TranslationLayout fromName(String? name) => values
      .firstWhere((v) => v.name == name, orElse: () => TranslationLayout.replace);
}

/// Readings over kanji: none, over words harder than the reader's level
/// (and words on no JLPT list), or over all.
enum FuriganaMode {
  off,
  hard,
  all;

  static FuriganaMode fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => FuriganaMode.off);
}

@immutable
class StudySettingsData {
  const StudySettingsData({
    this.layout = TranslationLayout.replace,
    this.furigana = FuriganaMode.off,
    this.level = 4,
    this.wordTap = false,
  });

  final TranslationLayout layout;
  final FuriganaMode furigana;

  /// The JLPT level the reader is at: 5 (N5) .. 1 (N1).
  final int level;
  final bool wordTap;

  /// Furigana or word taps need the word tools.
  bool get needsTools => furigana != FuriganaMode.off || wordTap;

  StudySettingsData copyWith({
    TranslationLayout? layout,
    FuriganaMode? furigana,
    int? level,
    bool? wordTap,
  }) =>
      StudySettingsData(
        layout: layout ?? this.layout,
        furigana: furigana ?? this.furigana,
        level: (level ?? this.level).clamp(1, 5),
        wordTap: wordTap ?? this.wordTap,
      );

  Map<String, Object> toJson() => {
        'layout': layout.name,
        'furigana': furigana.name,
        'level': level,
        'wordTap': wordTap,
      };

  factory StudySettingsData.fromJson(Map<String, dynamic> j) =>
      const StudySettingsData().copyWith(
        layout: TranslationLayout.fromName(j['layout'] as String?),
        furigana: FuriganaMode.fromName(j['furigana'] as String?),
        level: (j['level'] as num?)?.toInt(),
        wordTap: j['wordTap'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is StudySettingsData &&
      other.layout == layout &&
      other.furigana == furigana &&
      other.level == level &&
      other.wordTap == wordTap;

  @override
  int get hashCode => Object.hash(layout, furigana, level, wordTap);
}

class StudySettings extends ValueNotifier<StudySettingsData> {
  StudySettings({MyLibraryDb? database})
      : _database = database,
        super(const StudySettingsData());

  static final StudySettings instance = StudySettings();
  static const pref = 'studySettings';

  final MyLibraryDb? _database;
  MyLibraryDb get _db => _database ?? MyLibraryDb.instance;
  Future<void>? _loading;
  bool _changed = false;

  Future<void> load() => _loading ??= () async {
        try {
          final saved = await _db.getPreference(pref).catchError((_) => null);
          if (!_changed && saved is String && saved.isNotEmpty) {
            value = StudySettingsData.fromJson(
                jsonDecode(saved) as Map<String, dynamic>);
          }
        } catch (_) {}
      }();

  Future<void> update(StudySettingsData next) async {
    if (next == value) return;
    _changed = true;
    value = next;
    await _db
        .savePreference(pref, jsonEncode(next.toJson()))
        .catchError((_) {});
  }

  @visibleForTesting
  void debugSet(StudySettingsData data) {
    _changed = true;
    _loading = Future.value();
    value = data;
  }
}
