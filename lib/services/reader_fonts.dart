// Fonts per script: the reader (and the app) can show Korean, Japanese
// and Latin text each in a font of the user's choice.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Package imports:
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';

enum FontScript { korean, japanese, latin }

/// A font option: the system font, a Google Font (downloaded once, then
/// cached on the device), or a font file the user imported.
@immutable
class FontChoice {
  /// `system`, `google:<Family>` or `file:<family>`.
  final String id;
  const FontChoice(this.id);

  static const system = FontChoice('system');

  bool get isSystem => id == 'system';
  bool get isGoogle => id.startsWith('google:');
  bool get isFile => id.startsWith('file:');
  String get family => id.substring(id.indexOf(':') + 1);

  String get label => isSystem ? '' : family;

  @override
  bool operator ==(Object other) => other is FontChoice && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Google Fonts offered per script: book (serif/mincho) faces first.
const googleFontsByScript = {
  FontScript.korean: [
    'Noto Serif KR',
    'Nanum Myeongjo',
    'Gowun Batang',
    'Hahmlet',
    'Noto Sans KR',
    'Nanum Gothic',
    'Gowun Dodum',
  ],
  FontScript.japanese: [
    'Noto Serif JP',
    'Shippori Mincho',
    'Zen Old Mincho',
    'BIZ UDPMincho',
    'Noto Sans JP',
    'BIZ UDPGothic',
    'M PLUS 1p',
    'Zen Maru Gothic',
  ],
  FontScript.latin: [
    'Literata',
    'Merriweather',
    'Lora',
    'Source Serif 4',
    'Nunito',
  ],
};

String _prefFor(FontScript script) => 'font_${script.name}';

/// Which script a piece of text is mostly in. Chinese characters without
/// kana or hangul follow [hanAs] (the book's language), defaulting to
/// Japanese.
FontScript scriptOf(String text, {FontScript hanAs = FontScript.japanese}) {
  if (RegExp(r'[가-힣ᄀ-ᇿ㄰-㆏]').hasMatch(text)) {
    return FontScript.korean;
  }
  if (RegExp(r'[぀-ヿ]').hasMatch(text)) return FontScript.japanese;
  if (RegExp(r'[一-鿿]').hasMatch(text)) return hanAs;
  return FontScript.latin;
}

/// The chosen fonts, kept in preferences, and the font files imported by
/// the user (registered with the engine at start-up).
class ReaderFonts extends ChangeNotifier {
  ReaderFonts._();
  static final ReaderFonts instance = ReaderFonts._();

  final Map<FontScript, FontChoice> _choices = {
    for (final s in FontScript.values) s: FontChoice.system,
  };
  final List<String> _importedFamilies = [];
  bool _loaded = false;

  List<String> get importedFamilies => List.unmodifiable(_importedFamilies);
  FontChoice choiceFor(FontScript script) => _choices[script]!;

  static Future<Directory> _fontDir() async {
    final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'fonts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load({MyLibraryDb? database}) async {
    if (_loaded) return;
    _loaded = true;
    final db = database ?? MyLibraryDb.instance;
    for (final script in FontScript.values) {
      final saved =
          await db.getPreference(_prefFor(script)).catchError((_) => null);
      if (saved is String && saved.isNotEmpty) {
        _choices[script] = FontChoice(saved);
      }
    }
    try {
      final dir = await _fontDir();
      await for (final entity in dir.list()) {
        if (entity is File) await _register(entity);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _register(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') return;
    final family = p.basenameWithoutExtension(file.path);
    final loader = FontLoader(family)
      ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
    if (!_importedFamilies.contains(family)) _importedFamilies.add(family);
  }

  /// Copies a .ttf/.otf file into the app and makes it selectable.
  Future<String> importFontFile(String path) async {
    final ext = p.extension(path).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') {
      throw ArgumentError('Not a .ttf or .otf font: $path');
    }
    final dir = await _fontDir();
    final target = File(p.join(dir.path, p.basename(path)));
    await File(path).copy(target.path);
    await _register(target);
    notifyListeners();
    return p.basenameWithoutExtension(path);
  }

  Future<void> choose(FontScript script, FontChoice choice,
      {MyLibraryDb? database}) async {
    _choices[script] = choice;
    notifyListeners();
    await (database ?? MyLibraryDb.instance)
        .savePreference(_prefFor(script), choice.id)
        .catchError((_) {});
  }

  /// The font family for [choice], or null for the system font. Google
  /// Fonts are fetched in the background the first time and cached; until
  /// then the system font shows.
  String? familyOf(FontChoice choice) {
    if (choice.isSystem) return null;
    if (choice.isFile) return choice.family;
    try {
      return GoogleFonts.getFont(choice.family).fontFamily;
    } catch (_) {
      return null;
    }
  }

  /// [base] in the font chosen for [script], with the others as fallbacks.
  TextStyle styleForScript(FontScript script, TextStyle base) {
    final primary = familyOf(_choices[script]!);
    final fallbacks = [
      for (final s in FontScript.values)
        if (s != script) familyOf(_choices[s]!),
    ].whereType<String>().toList();
    if (primary == null && fallbacks.isEmpty) return base;
    return base.copyWith(
      fontFamily: primary ?? base.fontFamily,
      fontFamilyFallback: [...fallbacks, ...?base.fontFamilyFallback],
    );
  }

  /// [base] in the font chosen for [text]'s script, with the other chosen
  /// fonts as fallbacks for mixed text.
  TextStyle styleFor(String text, TextStyle base,
      {FontScript hanAs = FontScript.japanese}) {
    return styleForScript(scriptOf(text, hanAs: hanAs), base);
  }

  /// The script of a language code (`ko`, `ja-JP`, `jpn`, `en`).
  static FontScript scriptForLanguage(String? code) {
    final c = (code ?? '').toLowerCase();
    if (c.startsWith('ko') || c == 'kor') return FontScript.korean;
    if (c.startsWith('ja') || c == 'jpn') return FontScript.japanese;
    return FontScript.latin;
  }

  /// The family the app UI uses for [languageCode] (ko/ja follow their
  /// script's choice), or null to keep the theme font.
  String? uiFamilyFor(String languageCode) {
    final script = languageCode == 'ko'
        ? FontScript.korean
        : languageCode == 'ja'
            ? FontScript.japanese
            : FontScript.latin;
    return familyOf(_choices[script]!);
  }
}
