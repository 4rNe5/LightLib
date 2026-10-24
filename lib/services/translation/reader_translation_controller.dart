// What the reader asks the translator for, and in which order.

// Dart imports:
import 'dart:async';
import 'dart:collection';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/translation/book_glossary.dart';
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

  /// The book's ruby readings ([epubRubyReadings]), once known.
  Map<String, String> readings = const {};

  /// The book's glossary ([GlossaryService]), once known.
  BookGlossary glossary = BookGlossary.empty;
  final int keepBehind;
  final AppLogger _logger = AppLogger();

  final SplayTreeMap<int, String> _queue = SplayTreeMap();
  final Set<String> _failed = {};

  /// Paragraphs that failed once; they get one more try, at the back of
  /// the queue, before counting as failed.
  final Set<String> _retried = {};
  final Set<String> _inFlight = {};
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  bool _modelLoaded = false;
  int _done = 0;
  String? _error;

  String? Function(int index)? _textAt;
  int _itemCount = 0;
  int _lastIndex = 0;
  int? _lastVisibleEnd;

  /// Paragraphs near the reading position that could not be translated
  /// (after the retry); they stay in the original until [retry].
  int get failedCount => _failed.length;

  String? get error => _error;
  String? get deviceLabel => _translator.deviceLabel;
  int get pendingCount => _queue.length + _inFlight.length;
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
      _inFlight.contains(text) || _queue.containsValue(text);

  /// Queues paragraph [index] and the [lookahead] paragraphs after it.
  /// [textAt] gives a paragraph's translatable text, or null for one that
  /// needs no translation (an image, a scene break).
  ///
  /// [visibleEnd] is the last paragraph on screen when more than one is
  /// (a page): everything up to it is queued, and [lookahead] after it.
  /// Without it a page longer than the lookahead kept its last paragraphs
  /// in the original language.
  void ensureAhead(
    int index, {
    required String? Function(int index) textAt,
    required int itemCount,
    int? visibleEnd,
  }) {
    if (_disposed) return;
    _textAt = textAt;
    _itemCount = itemCount;
    _lastIndex = index;
    _lastVisibleEnd = visibleEnd;
    final last = visibleEnd != null && visibleEnd > index ? visibleEnd : index;
    var changed = false;

    // Forget what the reader has moved far away from.
    final low = index - keepBehind - lookahead;
    final high = last + lookahead * 3;
    final stale = _queue.keys.where((k) => k < low || k > high).toList();
    for (final k in stale) {
      _queue.remove(k);
      changed = true;
    }

    final end = (last + lookahead).clamp(0, itemCount - 1);
    for (var i = index; i <= end; i++) {
      if (_queue.containsKey(i)) continue;
      final text = textAt(i);
      if (text == null || text.isEmpty) continue;
      if (_cache.lookup(text) != null || _failed.contains(text)) continue;
      if (_inFlight.contains(text)) continue;
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
    _retried.clear();
    notifyListeners();
    final textAt = _textAt;
    if (textAt != null) {
      // Back to where the reader is: the failed paragraphs there are
      // queued again (an empty queue used to leave them untouched).
      ensureAhead(_queue.isNotEmpty ? _queue.firstKey()! : _lastIndex,
          textAt: textAt, itemCount: _itemCount, visibleEnd: _lastVisibleEnd);
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
      while (!_disposed &&
          !_paused &&
          (_queue.isNotEmpty || _retryLater.isNotEmpty)) {
        if (_queue.isEmpty) {
          _queue.addAll(_retryLater);
          _retryLater.clear();
        }
        // The first waiting paragraph and the ones right after it, in one
        // request when the translator takes several (a line-broken
        // paragraph goes alone: its lines are translated one by one).
        final first = _queue.entries.first;
        final batch = <MapEntry<int, String>>[first];
        final size = first.value.contains('\n') ? 1 : _translator.batchSize;
        for (final e in _queue.entries.skip(1)) {
          if (batch.length >= size) break;
          if (!_adjacent(batch.last.key, e.key) || e.value.contains('\n')) {
            break;
          }
          batch.add(e);
        }
        for (final e in batch) {
          _queue.remove(e.key);
        }
        batch.removeWhere((e) => _cache.lookup(e.value) != null);
        if (batch.isEmpty) continue;
        _inFlight.addAll(batch.map((e) => e.value));
        notifyListeners();
        try {
          if (!_modelLoaded) {
            await _translator.load();
            _modelLoaded = true;
            notifyListeners();
          }
          final textAt = _textAt;
          // On screen first; what comes next is paced.
          final priority = batch.first.key <= (_lastVisibleEnd ?? _lastIndex)
              ? TranslationPriority.visible
              : TranslationPriority.ahead;
          if (batch.length == 1) {
            final entry = batch.single;
            final out = await _translator.translate(entry.value,
                targetLanguage: targetLanguage,
                sourceLanguage: sourceLanguage,
                context: precedingContext(entry.key, textAt),
                following: textAt == null ? null : textAt(entry.key + 1),
                priority: priority);
            if (_disposed) return;
            _settle(entry, out);
          } else {
            final before = <String>[];
            for (var k = batch.first.key - 1;
                k >= 0 && k >= batch.first.key - 3 && textAt != null;
                k--) {
              final t = textAt(k);
              if (t != null && t.isNotEmpty) before.insert(0, t);
            }
            final outs = await _translator.translateBatch(
              [for (final e in batch) e.value],
              targetLanguage: targetLanguage,
              sourceLanguage: sourceLanguage,
              before: before,
              beforeTranslations: [for (final t in before) _cache.lookup(t)],
              readings: readings,
              glossary: glossary,
              priority: priority,
              onEach: (i, out) {
                if (_disposed || out.isEmpty) return;
                // Shown as soon as it is ready, not when the batch ends.
                _cache.store(batch[i].value, out);
                _inFlight.remove(batch[i].value);
                _done++;
                notifyListeners();
              },
            );
            if (_disposed) return;
            for (var i = 0; i < batch.length; i++) {
              if (_cache.lookup(batch[i].value) != null) continue;
              _settle(batch[i], outs[i]);
            }
          }
        } catch (e) {
          _logger.warning('Paragraph translation failed',
              tag: 'ReaderTranslation', error: e);
          if (!_modelLoaded) {
            // The model itself did not load: every paragraph would fail
            // the same way, so stop and say so.
            _error = e.toString();
            for (final entry in batch) {
              _queue[entry.key] = entry.value;
            }
            return;
          }
          for (final entry in batch) {
            if (_cache.lookup(entry.value) == null) {
              _failOnce(entry.key, entry.value);
            }
          }
        } finally {
          _inFlight.removeAll(batch.map((e) => e.value));
          if (!_disposed) notifyListeners();
        }
      }
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Whether nothing to translate lies between paragraphs [a] and [b]
  /// (pictures and done paragraphs in between keep them one passage).
  bool _adjacent(int a, int b) {
    if (b <= a) return false;
    final textAt = _textAt;
    for (var k = a + 1; k < b; k++) {
      final t = textAt?.call(k);
      if (t != null && t.isNotEmpty && _cache.lookup(t) == null) return false;
    }
    return b - a <= 4;
  }

  void _settle(MapEntry<int, String> entry, String out) {
    if (out.isEmpty) {
      _failOnce(entry.key, entry.value);
    } else {
      _cache.store(entry.value, out);
      _done++;
    }
  }

  /// First failure: one more try after the rest of the queue (it runs
  /// in index order, so a key past the window would never run - the text
  /// goes back under its own index once the queue drains). Second: failed.
  void _failOnce(int index, String text) {
    if (_retried.add(text)) {
      _retryLater[index] = text;
    } else {
      _failed.add(text);
    }
  }

  final Map<int, String> _retryLater = {};

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
