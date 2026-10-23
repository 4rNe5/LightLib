// Reader appearance: theme, type size and spacing, margins, alignment
// and layout - the settings in the reader's "Themes & Settings" sheet.

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/ui/components/paged_book_view.dart' show ReaderLayout;

/// The page colours of a reader theme.
enum ReaderThemeId {
  /// Follows the app's light/dark theme.
  original,
  paper,
  calm,
  quiet,
  bold,
  night;

  static ReaderThemeId fromName(String? name) => ReaderThemeId.values
      .firstWhere((t) => t.name == name, orElse: () => ReaderThemeId.original);
}

@immutable
class ReaderPalette {
  final Color background;
  final Color text;
  final Color secondaryText;
  final bool dark;

  /// The theme sets the text weight (Bold) regardless of the switch.
  final bool forceBold;

  const ReaderPalette({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.dark,
    this.forceBold = false,
  });
}

ReaderPalette paletteFor(ReaderThemeId theme, {required bool appDark}) {
  switch (theme) {
    case ReaderThemeId.original:
      return appDark
          ? const ReaderPalette(
              background: Color(0xFF121212),
              text: Color(0xFFF2F2F2),
              secondaryText: Color(0xFF9E9E9E),
              dark: true)
          : const ReaderPalette(
              background: Color(0xFFFFFFFF),
              text: Color(0xFF111111),
              secondaryText: Color(0xFF6E6E73),
              dark: false);
    case ReaderThemeId.paper:
      return const ReaderPalette(
          background: Color(0xFFF8F1E3),
          text: Color(0xFF3B2F25),
          secondaryText: Color(0xFF8A7A66),
          dark: false);
    case ReaderThemeId.calm:
      return const ReaderPalette(
          background: Color(0xFFE6D9BF),
          text: Color(0xFF3A2E1F),
          secondaryText: Color(0xFF7D6B52),
          dark: false);
    case ReaderThemeId.quiet:
      return const ReaderPalette(
          background: Color(0xFF4A4A4F),
          text: Color(0xFFD9D9DE),
          secondaryText: Color(0xFFA0A0A8),
          dark: true);
    case ReaderThemeId.bold:
      return appDark
          ? const ReaderPalette(
              background: Color(0xFF121212),
              text: Color(0xFFFFFFFF),
              secondaryText: Color(0xFFAAAAAA),
              dark: true,
              forceBold: true)
          : const ReaderPalette(
              background: Color(0xFFFFFFFF),
              text: Color(0xFF000000),
              secondaryText: Color(0xFF555555),
              dark: false,
              forceBold: true);
    case ReaderThemeId.night:
      return const ReaderPalette(
          background: Color(0xFF000000),
          text: Color(0xFFB8B8B8),
          secondaryText: Color(0xFF6E6E6E),
          dark: true);
  }
}

/// One immutable set of reader settings.
@immutable
class ReaderSettingsData {
  static const minFontSize = 10.0;
  static const maxFontSize = 36.0;
  static const minLineHeight = 1.2;
  static const maxLineHeight = 2.4;
  static const minLetterSpacing = -0.5;
  static const maxLetterSpacing = 2.0;
  static const minMargin = 4.0;
  static const maxMargin = 48.0;

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double margin;
  final bool justify;
  final bool boldText;
  final ReaderThemeId theme;
  final ReaderLayout layout;

  const ReaderSettingsData({
    this.fontSize = 17,
    this.lineHeight = 1.7,
    this.letterSpacing = 0,
    this.margin = 22,
    this.justify = false,
    this.boldText = false,
    this.theme = ReaderThemeId.original,
    this.layout = ReaderLayout.scroll,
  });

  ReaderSettingsData copyWith({
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? margin,
    bool? justify,
    bool? boldText,
    ReaderThemeId? theme,
    ReaderLayout? layout,
  }) {
    return ReaderSettingsData(
      fontSize: (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize),
      lineHeight:
          (lineHeight ?? this.lineHeight).clamp(minLineHeight, maxLineHeight),
      letterSpacing: (letterSpacing ?? this.letterSpacing)
          .clamp(minLetterSpacing, maxLetterSpacing),
      margin: (margin ?? this.margin).clamp(minMargin, maxMargin),
      justify: justify ?? this.justify,
      boldText: boldText ?? this.boldText,
      theme: theme ?? this.theme,
      layout: layout ?? this.layout,
    );
  }

  /// Everything except the layout and theme back to defaults.
  ReaderSettingsData resetTypography() =>
      ReaderSettingsData(theme: theme, layout: layout);

  Map<String, Object> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'margin': margin,
        'justify': justify,
        'boldText': boldText,
        'theme': theme.name,
        'layout': layout.name,
      };

  static ReaderSettingsData fromJson(Map<String, dynamic> json) {
    // Hand-edited or older values of the wrong type fall back quietly.
    double? d(String key) {
      final v = json[key];
      return v is num ? v.toDouble() : null;
    }

    bool? b(String key) {
      final v = json[key];
      return v is bool ? v : null;
    }

    String? str(String key) {
      final v = json[key];
      return v is String ? v : null;
    }

    return const ReaderSettingsData().copyWith(
      fontSize: d('fontSize'),
      lineHeight: d('lineHeight'),
      letterSpacing: d('letterSpacing'),
      margin: d('margin'),
      justify: b('justify'),
      boldText: b('boldText'),
      theme: ReaderThemeId.fromName(str('theme')),
      layout: ReaderLayout.fromName(str('layout')),
    );
  }

  bool boldFor(ReaderPalette palette) => boldText || palette.forceBold;

  @override
  bool operator ==(Object other) =>
      other is ReaderSettingsData &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The reader settings, shared by every open book and saved as one
/// preference.
class ReaderSettings extends ChangeNotifier {
  ReaderSettings({MyLibraryDb? database}) : _database = database;

  static final ReaderSettings instance = ReaderSettings();

  static const pref = 'readerSettings';
  static const _legacyFontSizePref = 'readerFontSize';
  static const _legacyLayoutPref = 'readerLayout';

  final MyLibraryDb? _database;
  MyLibraryDb get _db => _database ?? MyLibraryDb.instance;

  ReaderSettingsData _value = const ReaderSettingsData();
  bool _loaded = false;
  Future<void>? _loading;

  /// Set by [update]: a change made while the saved settings were still
  /// loading must not be overwritten when they arrive.
  bool _changedBeforeLoad = false;

  ReaderSettingsData get value => _value;
  bool get loaded => _loaded;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final loaded = await _read();
    if (!_changedBeforeLoad && loaded != null) _value = loaded;
    _loaded = true;
    notifyListeners();
  }

  Future<ReaderSettingsData?> _read() async {
    try {
      final saved = await _db.getPreference(pref).catchError((_) => null);
      if (saved is String && saved.isNotEmpty) {
        return ReaderSettingsData.fromJson(
            jsonDecode(saved) as Map<String, dynamic>);
      } else {
        // Settings saved before the sheet existed.
        final size = await _db
            .getPreference(_legacyFontSizePref)
            .catchError((_) => null);
        final layout =
            await _db.getPreference(_legacyLayoutPref).catchError((_) => null);
        return const ReaderSettingsData().copyWith(
          fontSize: double.tryParse('$size'),
          layout: ReaderLayout.fromName(layout as String?),
        );
      }
    } catch (_) {
      // Unreadable: defaults.
      return null;
    }
  }

  Future<void> update(ReaderSettingsData next) async {
    if (next == _value) return;
    if (!_loaded) _changedBeforeLoad = true;
    _value = next;
    notifyListeners();
    await _db
        .savePreference(pref, jsonEncode(next.toJson()))
        .catchError((_) {});
  }

  /// Test hook.
  @visibleForTesting
  void resetForTest() {
    _value = const ReaderSettingsData();
    _loaded = false;
    _loading = null;
    _changedBeforeLoad = false;
  }
}
