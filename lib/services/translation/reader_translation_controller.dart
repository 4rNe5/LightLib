// What the reader asks the translator for, and in which order.

// Dart imports:
import 'dart:async';
import 'dart:collection';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translator.dart';

enum ReaderTranslationStatus { loadingModel, translating, idle, paused, error }

/// Translates the paragraphs around the reading position, one at a time,
/// nearest-first, and remembers the results.
///
/// The chapter builder calls [ensureAhead] for each paragraph it shows, so
/// opening a chapter queues what is on screen plus [lookahead] paragraphs
/// after it - not the whole book, which would cost far more battery than
/// reading needs. Paragraphs the reader has scrolled far away from are
/// dropped from the queue.
class ReaderTranslationController extends ChangeNotifier {
  ReaderTranslationController({
    required Translator translator,
    required TranslationCache cache,
    required this.targetLanguage,
    this.sourceLanguage,
    this.lookahead = 12,
    this.keepBehind = 4,
  })  : _translator = translator,
        _cache = cache;

  final Translator _translator;
  final TranslationCache _cache;
  final String targetLanguage;
  final String? sourceLanguage;
  final int lookahead;
  final int keepBehind;
  final AppLogger _logger = AppLogger();

  final SplayTreeMap<int, String> _queue = SplayTreeMap();
  final Set<String> _failed = {};
  String? _inFlight;
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  bool _modelLoaded = false;
  int _done = 0;
  String? _error;

  String? Function(int index)? _textAt;
  int _itemCount = 0;

  String? get error => _error;
  String? get deviceLabel => _translator.deviceLabel;
  int get pendingCount => _queue.length + (_inFlight == null ? 0 : 1);
  int get translatedThisSession => _done;

  ReaderTranslationStatus get status {
    if (_error != null) return ReaderTranslationStatus.error;
    if (_paused) return ReaderTranslationStatus.paused;
    if (_running && !_modelLoaded) return ReaderTranslationStatus.loadingModel;
    if (_running) return ReaderTranslationStatus.translating;
    return ReaderTranslationStatus.idle;
  }

  /// The cached translation of [text], or null when there is none yet.
  String? translationOf(String text) => _cache.lookup(text);

  bool isPending(String text) =>
      _inFlight == text || _queue.containsValue(text);

  /// Queues paragraph [index] and the [lookahead] paragraphs after it.
  /// [textAt] gives a paragraph's translatable text, or null for one that
  /// needs no translation (an image, a scene break).
  void ensureAhead(
    int index, {
    required String? Function(int index) textAt,
    required int itemCount,
  }) {
    if (_disposed) return;
    _textAt = textAt;
    _itemCount = itemCount;
    var changed = false;

    // Forget what the reader has moved far away from.
    final low = index - keepBehind - lookahead;
    final high = index + lookahead * 3;
    final stale = _queue.keys.where((k) => k < low || k > high).toList();
    for (final k in stale) {
      _queue.remove(k);
      changed = true;
    }

    final end = (index + lookahead).clamp(0, itemCount - 1);
    for (var i = index; i <= end; i++) {
      if (_queue.containsKey(i)) continue;
      final text = textAt(i);
      if (text == null || text.isEmpty) continue;
      if (_cache.lookup(text) != null || _failed.contains(text)) continue;
      if (_inFlight == text) continue;
      _queue[i] = text;
      changed = true;
    }
    // Called from build: listeners (the reader's setState) must not run
    // until the frame is done.
    if (changed) _notifySoon();
    scheduleMicrotask(_pump);
  }

  bool _notifyScheduled = false;
  void _notifySoon() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Stops starting new paragraphs (the app went to the background); the
  /// one in progress finishes.
  void pause() {
    if (_paused) return;
    _paused = true;
    notifyListeners();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    notifyListeners();
    _pump();
  }

  /// Clears an error so the queue runs again.
  void retry() {
    _error = null;
    _failed.clear();
    notifyListeners();
    final textAt = _textAt;
    if (textAt != null && _queue.isNotEmpty) {
      ensureAhead(_queue.firstKey()!, textAt: textAt, itemCount: _itemCount);
    } else {
      _pump();
    }
  }

  void _pump() {
    if (_running || _paused || _disposed || _error != null || _queue.isEmpty) {
      return;
    }
    _running = true;
    notifyListeners();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      while (!_disposed && !_paused && _queue.isNotEmpty) {
        final entry = _queue.entries.first;
        _queue.remove(entry.key);
        final text = entry.value;
        if (_cache.lookup(text) != null) continue;
        _inFlight = text;
        notifyListeners();
        try {
          if (!_modelLoaded) {
            await _translator.load();
            _modelLoaded = true;
            notifyListeners();
          }
          final out = await _translator.translate(text,
              targetLanguage: targetLanguage,
              sourceLanguage: sourceLanguage,
              urgent: true);
          if (_disposed) return;
          if (out.isEmpty) {
            _failed.add(text);
          } else {
            _cache.store(text, out);
            _done++;
          }
        } catch (e) {
          _logger.warning('Paragraph translation failed',
              tag: 'ReaderTranslation', error: e);
          if (!_modelLoaded) {
            // The model itself did not load: every paragraph would fail
            // the same way, so stop and say so.
            _error = e.toString();
            _queue[entry.key] = text;
            return;
          }
          _failed.add(text);
        } finally {
          _inFlight = null;
          if (!_disposed) notifyListeners();
        }
      }
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    // Saving is best effort: losing it only costs re-translating.
    unawaited(_cache.flush().catchError((_) {}));
    unawaited(_translator.dispose());
    super.dispose();
  }
}

/// Up to [maxChars] of the translatable text just before paragraph
/// [index] - the context a translation is made with, so who speaks and
/// what things are called stay consistent from paragraph to paragraph.
String? precedingContext(int index, String? Function(int index)? textAt,
    {int maxChars = 240}) {
  if (textAt == null) return null;
  final parts = <String>[];
  var length = 0;
  for (var i = index - 1; i >= 0 && i >= index - 6; i--) {
    final t = textAt(i);
    if (t == null || t.isEmpty) continue;
    if (length + t.length > maxChars && parts.isNotEmpty) break;
    parts.insert(0, t);
    length += t.length;
    if (length >= maxChars) break;
  }
  if (parts.isEmpty) return null;
  final joined = parts.join('\n');
  return joined.length > maxChars
      ? joined.substring(joined.length - maxChars)
      : joined;
}
