// A [Translator] on Gemini: many paragraphs per request, the answer
// constrained to exactly one translation each, the app's own style
// instructions and the book's glossary. What Gemini cannot translate goes
// to the model on the phone (the day's quota, a filter, no connection) -
// except paragraphs the API refuses under its own policy whatever the
// settings say: those stay in the original, and are not sent elsewhere.

// Dart imports:
import 'dart:async';
import 'dart:convert';

// Project imports:
import 'package:openlib/services/epub_package.dart' show readingsIn;
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/translation/book_glossary.dart';
import 'package:openlib/services/translation/gemini/gemini_api.dart';
import 'package:openlib/services/translation/gemini/gemini_client.dart';
import 'package:openlib/services/translation/gemini/gemini_settings.dart';
import 'package:openlib/services/translation/paragraph_text.dart'
    show cleanTranslation, leftoverSourceScript;
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/services/translation/translation_qa.dart';
import 'package:openlib/services/translation/translation_style.dart';
import 'package:openlib/services/translation/translator.dart';

/// The instructions (system) and the request (user) for [texts].
({String system, String user}) cloudTranslationPrompt({
  required List<String> texts,
  required String targetLanguage,
  String? sourceLanguage,
  List<String> before = const [],
  List<String?> beforeTranslations = const [],
  List<MapEntry<String, String>> readings = const [],
  List<GlossaryEntry> glossary = const [],
  bool lightNovelStyle = true,
  String? narration,
}) {
  final system = StringBuffer(batchPromptHead(
      texts: texts,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      lightNovelStyle: lightNovelStyle,
      narration: narration));
  if (glossary.isNotEmpty) {
    system
      ..writeln()
      ..writeln()
      ..writeln('Names and terms in this book - write them exactly like this '
          '(a gender tells how that person speaks and is spoken of):');
    for (final e in glossary) {
      system.writeln(e.promptLine);
    }
  }
  // The instructions are the same for every request of a book (the
  // style, how it is narrated, all its names): what changes from one
  // request to the next - the readings its paragraphs happen to carry -
  // goes with the paragraphs.
  final covered = {for (final e in glossary) e.source};
  final hints = [
    for (final r in readings)
      if (!covered.any((c) => c.contains(r.key))) r,
  ];
  system
    ..writeln()
    ..writeln()
    ..write('You receive JSON: "context" is the story just before, already '
        'translated - read it for the flow, never translate or repeat it. '
        '"readings", when given, says how words of these paragraphs are '
        'read: write a name as it is read, in $targetLanguage letters, and '
        'translate an ordinary word by its meaning. '
        '"paragraphs" are the numbered paragraphs to translate. Answer with '
        '{"translations": [{"n": 1, "text": "..."}, ...]}: for each '
        'paragraph its number and its $targetLanguage translation, in '
        'order - never merge, split, skip or add paragraphs, and add no '
        'notes or explanations of your own.');

  final user = {
    if (before.isNotEmpty)
      'context': [
        for (var i = 0; i < before.length; i++)
          {
            'text': before[i],
            if (i < beforeTranslations.length &&
                (beforeTranslations[i] ?? '').isNotEmpty)
              'translation': beforeTranslations[i],
          }
      ],
    if (hints.isNotEmpty) 'readings': {for (final r in hints) r.key: r.value},
    'paragraphs': [
      for (var i = 0; i < texts.length; i++) {'n': i + 1, 'text': texts[i]}
    ],
  };
  return (
    system: system.toString(),
    user: 'Translate the ${texts.length} paragraphs.\n${jsonEncode(user)}',
  );
}

/// A request to correct [items]: each source, its draft and what is
/// wrong with it; answered like a translation request.
String cloudRefinementRequest(
    List<
            ({
              String source,
              String draft,
              List<String> problems,
              List<String> before,
            })>
        items,
    String targetLanguage) {
  return 'These $targetLanguage translations failed a check. Correct each '
      'one (the problems are listed with it), keeping everything that was '
      'right, and answer with {"translations": [{"n": 1, "text": "..."}, '
      '...]}: for each item its number and the corrected translation.\n'
      '${jsonEncode({
        'items': [
          for (var k = 0; k < items.length; k++)
            {
              'n': k + 1,
              // The story just before, in Korean: who is spoken of.
              if (items[k].before.isNotEmpty) 'before': items[k].before,
              'source': items[k].source,
              'draft': items[k].draft,
              'problems': items[k].problems,
            }
        ]
      })}';
}

/// How alike two texts are (0 to 1, letter pairs shared, spaces and
/// punctuation aside).
double textSimilarity(String a, String b) {
  final strip = RegExp(r'[\s\p{P}\p{S}]', unicode: true);
  Map<String, int> pairs(String s) {
    final t = s.replaceAll(strip, '');
    final out = <String, int>{};
    for (var i = 0; i + 1 < t.length; i++) {
      final g = t.substring(i, i + 2);
      out[g] = (out[g] ?? 0) + 1;
    }
    return out;
  }

  final x = pairs(a), y = pairs(b);
  final total = x.values.fold<int>(0, (n, v) => n + v) +
      y.values.fold<int>(0, (n, v) => n + v);
  if (total == 0) return 0;
  var shared = 0;
  x.forEach((g, n) {
    final m = y[g];
    if (m != null) shared += n < m ? n : m;
  });
  return 2 * shared / total;
}

/// The first answer in [outs] that repeats the one before it (or the last
/// context translation [previous]) while its source is another sentence:
/// the answer slipped by one paragraph from there. Null when none does.
int? slippedAt(List<String> sources, List<String> outs, String? previous,
    String? previousSource) {
  for (var k = 0; k < outs.length; k++) {
    final before = k == 0 ? previous : outs[k - 1];
    final beforeSource = k == 0 ? previousSource : sources[k - 1];
    if (before == null || before.isEmpty || beforeSource == null) continue;
    // Short lines repeat by nature (「はい」, 「……」).
    if (outs[k].replaceAll(RegExp(r'\s'), '').length < 8) continue;
    if (textSimilarity(outs[k], before) >= 0.6 &&
        textSimilarity(sources[k], beforeSource) < 0.5) {
      return k;
    }
  }
  return null;
}

/// Which answers to a request to correct several paragraphs are not their
/// own paragraph's ([drafts]: what was sent, [corrected]: what came back,
/// in the same order; [before]: the story shown with each, if any). A
/// correction changes a draft a little; one that reads like another
/// item's draft, or like the story shown before it, or that came back
/// word for word for two different drafts, was put in the wrong place.
/// Any at all, and the whole answer is one that slipped: none of it is
/// to be used.
Set<int> misplacedCorrections(List<String> drafts, List<String> corrected,
    {List<List<String>> before = const []}) {
  final out = <int>{};
  String bare(String t) => t.replaceAll(RegExp(r'\s'), '');
  for (var k = 0; k < corrected.length; k++) {
    final mine = corrected[k];
    if (mine.isEmpty) continue;
    for (var j = 0; j < corrected.length; j++) {
      if (j == k) continue;
      // One text for two paragraphs that were not alike.
      if (bare(mine) == bare(corrected[j]) &&
          bare(drafts[k]) != bare(drafts[j]) &&
          textSimilarity(drafts[k], drafts[j]) < 0.9) {
        out
          ..add(k)
          ..add(j);
      }
    }
    // Too short to tell one line from another by its letters.
    if (bare(mine).length < 8) continue;
    final own = textSimilarity(mine, drafts[k]);
    for (var j = 0; j < drafts.length; j++) {
      if (j == k) continue;
      final other = textSimilarity(mine, drafts[j]);
      if (other >= 0.6 && other > own + 0.15) out.add(k);
    }
    if (k < before.length) {
      for (final line in before[k]) {
        final other = textSimilarity(mine, line);
        if (other >= 0.6 && other > own + 0.15) out.add(k);
      }
    }
  }
  return out;
}

/// A paragraph waiting to be sent back: its first answer and what is
/// wrong with it.
class _Held {
  _Held({
    required this.source,
    required this.sent,
    required this.draft,
    required this.issues,
    required this.before,
    required this.targetLanguage,
    required this.glossary,
    required this.system,
    required this.deliver,
    required this.fallback,
    required this.shown,
  });

  final String source;

  /// The draft as the model wrote it (kana and all), and as it is kept
  /// (polished) when the correction is no better.
  final String sent;
  final String draft;
  final List<QaIssue> issues;

  /// The story just before, in Korean, where the correction needs it.
  final List<String> before;
  final String targetLanguage;
  final BookGlossary glossary;

  /// The instructions the paragraph was translated under.
  final String system;
  final void Function(String translation) deliver;

  /// Nothing usable came: the phone, where the reader allows it.
  final Future<void> Function() fallback;

  /// The draft is already with the caller (a correction replaces it).
  final bool shown;
}

class CloudTranslator implements Translator {
  CloudTranslator({
    GeminiClient? client,
    GeminiSettings? settings,
    this.batchSize = 80,
    this.fixTense = true,
    this.fixPronouns = true,
    this.gatherCorrections = false,
    bool? polish,
    Future<Translator?> Function()? device,
  })  : _client = client ?? GeminiClient.shared,
        _settings = settings ?? GeminiSettings.instance,
        _polish = polish,
        _deviceSource = device;

  final GeminiClient _client;
  final GeminiSettings _settings;

  /// Sends back narration that slips into the present for a sentence
  /// ([tenseSlips]).
  final bool fixTense;

  /// Sends back paragraphs that carry 彼女 over as 그녀 ([leansOnShe]).
  final bool fixPronouns;

  /// Paragraphs to be sent back are held and sent together, about
  /// [correctionBatch] in a request ([flushCorrections] sends the rest),
  /// instead of a request of three or four after every translation
  /// request: a whole book takes about half the requests. Their first
  /// answers are handed over at once and replaced when the correction
  /// comes - except one too broken to show (text left untranslated, a
  /// sentence dropped), which waits for it. For a book translated on its
  /// own; the page on screen is corrected at once.
  final bool gatherCorrections;

  /// How many held paragraphs make a request.
  static const correctionBatch = 24;
  final List<_Held> _held = [];
  Future<void> _flushing = Future<void>.value();

  /// Sends back paragraphs thick with word-for-word constructions
  /// ([readsStiff]) to be said again in natural Korean: the reader's
  /// choice in settings (off by default - it asks more of the key), unless
  /// set here.
  bool get polish => _polish ?? _settings.polish;
  final bool? _polish;

  /// The model on the phone, made on first need (null: none installed).
  final Future<Translator?> Function()? _deviceSource;
  Future<Translator?>? _device;
  final AppLogger _logger = AppLogger();

  /// Paragraphs per request: the reader asks for a screenful at a time,
  /// a whole-book run for many more.
  @override
  final int batchSize;

  /// Requests that may be in flight at once for a book.
  int get concurrency => _settings.concurrency;

  @override
  String? get deviceLabel => 'Gemini';

  @override
  Future<void> load() async {}

  Future<Translator?> _onDevice() =>
      _device ??= (_deviceSource?.call() ?? Future<Translator?>.value())
          .catchError((_) => null);

  @override
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String? sourceLanguage,
    String? context,
    String? following,
    TranslationPriority priority = TranslationPriority.background,
  }) async {
    // One paragraph, answered here and now: nothing is held back.
    final out = await _translateBatch([text],
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        before: context == null ? const [] : [context],
        priority: priority,
        gather: false);
    return out.first;
  }

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String targetLanguage,
    String? sourceLanguage,
    List<String> before = const [],
    List<String?> beforeTranslations = const [],
    Map<String, String> readings = const {},
    BookGlossary glossary = BookGlossary.empty,
    TranslationPriority priority = TranslationPriority.background,
    void Function(int index, String translation)? onEach,
  }) =>
      _translateBatch(texts,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          before: before,
          beforeTranslations: beforeTranslations,
          readings: readings,
          glossary: glossary,
          priority: priority,
          onEach: onEach,
          gather: gatherCorrections);

  /// Sends what is held ([gatherCorrections]) and hands over what comes
  /// back, to the callers the paragraphs came from. Called when a book's
  /// run ends or stops; safe to call at any time. With [onlyFull], only
  /// while a whole request's worth is waiting (the rest waits for more).
  Future<void> flushCorrections({bool onlyFull = false}) {
    return _flushing = _flushing.then((_) async {
      while (onlyFull
          ? _held.length >= correctionBatch
          : _held.isNotEmpty) {
        // Those translated under the same instructions go together.
        final first = _held.first;
        final group = [
          for (final h in _held)
            if (h.system == first.system &&
                h.targetLanguage == first.targetLanguage)
              h,
        ].take(correctionBatch).toList();
        _held.removeWhere(group.contains);
        try {
          await _correct(group);
        } on GeminiError {
          // A key that stopped working: the drafts stand.
          for (final h in group) {
            if (!h.shown && h.draft.isNotEmpty) h.deliver(h.draft);
          }
        }
      }
    });
  }

  /// One request to correct [items]; each gets its correction if that is
  /// its own and better, its draft otherwise.
  Future<void> _correct(List<_Held> items) async {
    if (items.isEmpty) return;
    final language = items.first.targetLanguage;
    List<String>? fixed;
    if (!_settings.usage.exhausted) {
      try {
        final r = await _client.generate(
          system: items.first.system,
          user: cloudRefinementRequest([
            for (final h in items)
              (
                source: h.source,
                draft: h.sent,
                problems: [for (final q in h.issues) qaProblem(q, language)],
                before: h.before,
              ),
          ], language),
          schema: translationSchema(items.length),
          maxOutputTokens:
              (items.fold<int>(0, (n, h) => n + h.source.length * 3) + 1024)
                  .clamp(1024, 65536),
        );
        if (r.block == null) fixed = parseTranslations(r.text, items.length);
      } on GeminiError catch (e) {
        if (e.kind == GeminiErrorKind.badKey) rethrow;
      }
    }
    // An answer with a correction in the wrong place is one that slipped
    // (a paragraph twice, the rest a place late): none of it is used.
    if (fixed != null && items.length > 1) {
      final misplaced = misplacedCorrections(
          [for (final h in items) h.sent], fixed,
          before: [for (final h in items) h.before]);
      if (misplaced.isNotEmpty) {
        _logger.warning('Corrections out of place, not used',
            tag: 'Gemini',
            metadata: {'at': misplaced.join(','), 'of': items.length});
        fixed = null;
      }
    }
    var kept = 0;
    for (var k = 0; k < items.length; k++) {
      final h = items[k];
      var best = h.draft;
      final again = fixed?[k];
      if (again != null && again.isNotEmpty) {
        final polished = finishTranslation(
            cleanTranslation(again), h.source, h.targetLanguage, h.glossary);
        final after = checkTranslation(h.source, polished,
            targetLanguage: h.targetLanguage,
            glossary: h.glossary,
            also: {
              for (final q in h.issues)
                if (styleChecks.contains(q)) q,
            });
        if (polished.isNotEmpty && refinedIsBetter(h.issues, after)) {
          best = polished;
          kept++;
        }
      }
      if (best.isEmpty) {
        await h.fallback();
      } else if (!h.shown || best != h.draft) {
        h.deliver(best);
      }
    }
    if (items.length > 1 || gatherCorrections) {
      _logger.info('Corrections', tag: 'Gemini', metadata: {
        'sent': items.length,
        'kept': kept,
        'answered': fixed != null,
      });
    }
  }

  Future<List<String>> _translateBatch(
    List<String> texts, {
    required String targetLanguage,
    String? sourceLanguage,
    List<String> before = const [],
    List<String?> beforeTranslations = const [],
    Map<String, String> readings = const {},
    BookGlossary glossary = BookGlossary.empty,
    TranslationPriority priority = TranslationPriority.background,
    void Function(int index, String translation)? onEach,
    required bool gather,
  }) async {
    final results = List<String>.filled(texts.length, '');
    // Every paragraph's first answer, kept or not: the story as the model
    // told it, for a correction that has to know who is spoken of.
    final drafts = List<String>.filled(texts.length, '');
    void deliver(int i, String t) {
      results[i] = t;
      if (t.isNotEmpty) onEach?.call(i, t);
    }

    Future<void> onDevice(List<int> indexes) async {
      if (!_settings.deviceFallback) return;
      final device = await _onDevice();
      if (device == null) return;
      final outs = await device.translateBatch(
          [for (final i in indexes) texts[i]],
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          before: before,
          beforeTranslations: beforeTranslations,
          readings: readings,
          glossary: glossary,
          priority: priority,
          onEach: (k, t) => deliver(indexes[k], t));
      for (var k = 0; k < outs.length; k++) {
        if (results[indexes[k]].isEmpty && outs[k].isNotEmpty) {
          deliver(indexes[k], outs[k]);
        }
      }
      _settings.recordOnDevice(indexes.length);
    }

    /// The Korean of the two paragraphs before [i], as far as it is known.
    List<String> storyBefore(int i) => [
          for (var k = i - 2; k < i; k++)
            if (k >= 0 && results[k].isNotEmpty)
              results[k]
            else if (k >= 0 && drafts[k].isNotEmpty)
              drafts[k]
            else if (k < 0 &&
                beforeTranslations.length + k >= 0 &&
                (beforeTranslations[beforeTranslations.length + k] ?? '')
                    .isNotEmpty)
              beforeTranslations[beforeTranslations.length + k]!,
        ];

    Future<void> run(List<int> indexes, {int depth = 0}) async {
      if (_settings.usage.exhausted) return onDevice(indexes);
      final part = [for (final i in indexes) texts[i]];
      final prompt = cloudTranslationPrompt(
        texts: part,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        before: before,
        beforeTranslations: beforeTranslations,
        readings: readingsIn(readings, [...part, ...before]),
        // The whole book's names, the same with every request.
        glossary: glossary.forBook(),
        lightNovelStyle: TranslationStyle.lightNovel,
        narration: targetLanguage == 'Korean' ? glossary.narrationNote : null,
      );
      final GeminiResult result;
      try {
        result = await _client.generate(
          system: prompt.system,
          user: prompt.user,
          schema: translationSchema(part.length),
          maxOutputTokens:
              (part.fold<int>(0, (n, t) => n + t.length * 3) + 1024)
                  .clamp(1024, 65536),
          paragraphs: part.length,
        );
      } on GeminiError catch (e) {
        if (e.kind == GeminiErrorKind.badKey ||
            e.kind == GeminiErrorKind.badRequest) {
          rethrow;
        }
        // The day's quota, the service down, no connection.
        _logger.warning('Gemini unavailable, translating on the device',
            tag: 'Gemini', metadata: {'kind': e.kind.name});
        return onDevice(indexes);
      }
      final block = result.block;
      if (block != null) {
        // Find the paragraphs that were blocked: the rest still goes.
        if (indexes.length > 1) {
          final half = indexes.length ~/ 2;
          await run(indexes.sublist(0, half), depth: depth + 1);
          await run(indexes.sublist(half), depth: depth + 1);
          return;
        }
        _settings.recordBlocked(block, 1);
        _logger.info('Gemini blocked a paragraph',
            tag: 'Gemini', metadata: {'kind': block.name});
        if (block == GeminiBlockKind.prohibited) {
          // Refused under the API's own policy: kept as written, not
          // routed around the refusal.
          deliver(indexes.single, texts[indexes.single]);
          return;
        }
        return onDevice(indexes);
      }
      var got = parseTranslations(result.text, part.length);
      // An answer that slipped by a paragraph (one translated twice, the
      // rest one place late) is not used: asked again in smaller parts.
      if (got != null) {
        final first = indexes.first;
        final previous = first > 0 ? results[first - 1] : '';
        final slip = slippedAt(
            part,
            got,
            previous.isNotEmpty
                ? previous
                : (beforeTranslations.isNotEmpty
                    ? beforeTranslations.last
                    : null),
            first > 0 && previous.isNotEmpty
                ? texts[first - 1]
                : (before.isNotEmpty ? before.last : null));
        if (slip != null) {
          _logger.warning('Gemini answer slipped by a paragraph',
              tag: 'Gemini', metadata: {'at': slip, 'of': part.length});
          got = null;
        }
      }
      if (got == null || got.any((t) => t.isEmpty)) {
        // A cut-off or malformed answer: smaller requests, then the phone.
        if (indexes.length > 1 && depth < 3) {
          final half = indexes.length ~/ 2;
          await run(indexes.sublist(0, half), depth: depth + 1);
          await run(indexes.sublist(half), depth: depth + 1);
          return;
        }
        return onDevice(indexes);
      }
      // The same checks as the phone's translations: what fails goes
      // back once, all together, with its problems named.
      final flagged = <int, (String, String, List<QaIssue>)>{};
      // (A name of the glossary left in kanji is written out, not sent
      // back.)
      final cleanedAll = [
        for (var k = 0; k < got.length; k++)
          targetLanguage == 'Korean'
              ? enforceGlossary(
                  texts[indexes[k]], cleanTranslation(got[k]), glossary)
              : cleanTranslation(got[k]),
      ];
      final polishedAll = [
        for (var k = 0; k < got.length; k++)
          finishTranslation(
              cleanedAll[k], texts[indexes[k]], targetLanguage, glossary),
      ];
      // Style, read off the request as a whole: which paragraphs slip out
      // of a past-tense narration for a sentence.
      final korean = targetLanguage == 'Korean' && TranslationStyle.lightNovel;
      final slips = korean && fixTense
          ? tenseSlips(part, polishedAll, before: beforeTranslations)
          : const <int>{};
      var styleFlags = 0;
      for (var k = 0; k < got.length; k++) {
        final i = indexes[k];
        final cleaned = cleanedAll[k];
        final leftover =
            leftoverSourceScript(cleaned, targetLanguage).isNotEmpty;
        final polished = polishedAll[k];
        drafts[i] = polished;
        final issues = [
          if (leftover) QaIssue.leftoverSource,
          ...checkTranslation(texts[i], polished,
              targetLanguage: targetLanguage,
              glossary: glossary,
              also: {
                if (slips.contains(k)) QaIssue.tenseSlip,
                if (korean && fixPronouns) QaIssue.pronoun,
                if (korean && polish) QaIssue.stiff,
              }).where((q) => q != QaIssue.leftoverSource),
        ];
        if (issues.any(styleChecks.contains)) styleFlags++;
        if (issues.isEmpty) {
          deliver(i, polished);
        } else {
          // The model sees what it wrote (kana and all); the polished one
          // stays if the correction is no better.
          flagged[i] = (leftover ? cleaned : polished, polished, issues);
        }
      }
      if (flagged.isNotEmpty) {
        // Where in a request paragraphs fail tells whether long requests
        // tire the model (the owner's logs answer it).
        _logger.info('Paragraphs sent back', tag: 'Gemini', metadata: {
          'of': got.length,
          'at': [
            for (var k = 0; k < got.length; k++)
              if (flagged.containsKey(indexes[k])) k + 1,
          ].join(','),
          'style': styleFlags,
          'issues': {
            for (final q in QaIssue.values)
              if (flagged.values.any((f) => f.$3.contains(q)))
                q.name: flagged.values.where((f) => f.$3.contains(q)).length,
          },
        });
        final held = [
          for (final MapEntry(key: i, value: (sent, draft, issues))
              in flagged.entries)
            _Held(
              source: texts[i],
              sent: sent,
              draft: draft,
              issues: issues,
              before: issues.contains(QaIssue.pronoun)
                  ? storyBefore(i)
                  : const [],
              targetLanguage: targetLanguage,
              glossary: glossary,
              system: prompt.system,
              deliver: (t) => deliver(i, t),
              fallback: () => onDevice([i]),
              // A draft with text left untranslated or sentences missing
              // is not shown: it waits for its correction.
              shown: gather &&
                  draft.isNotEmpty &&
                  !issues.any(const {
                    QaIssue.leftoverSource,
                    QaIssue.repetition,
                    QaIssue.tooShort,
                    QaIssue.tooLong,
                  }.contains),
            ),
        ];
        if (!gather) {
          await _correct(held);
        } else {
          for (final h in held) {
            if (h.shown) h.deliver(h.draft);
          }
          _held.addAll(held);
          if (_held.length >= correctionBatch) {
            await flushCorrections(onlyFull: true);
          }
        }
      }
    }

    await run([for (var i = 0; i < texts.length; i++) i]);
    return results;
  }

  /// A request that is not a translation, answered as JSON after
  /// [schema] (a book's names, read off its whole text). Null when Gemini
  /// gives no answer - the day's quota, a block, an error other than a
  /// key that does not work: the caller then does without.
  Future<String?> analyse({
    required String system,
    required String user,
    required Map<String, Object?> schema,
    int maxOutputTokens = 8192,
  }) async {
    if (_settings.usage.exhausted) return null;
    try {
      final r = await _client.generate(
        system: system,
        user: user,
        schema: schema,
        maxOutputTokens: maxOutputTokens,
      );
      if (r.block != null || r.text.trim().isEmpty) return null;
      return r.text;
    } on GeminiError catch (e) {
      if (e.kind == GeminiErrorKind.badKey) rethrow;
      return null;
    }
  }

  @override
  Future<String?> complete(String prompt,
      {required int maxTokens,
      TranslationPriority priority = TranslationPriority.background,
      String? head}) async {
    if (_settings.usage.exhausted) {
      final device = await _onDevice();
      return device?.complete(prompt,
          maxTokens: maxTokens, priority: priority, head: head);
    }
    final split = head != null && prompt.startsWith(head);
    try {
      final r = await _client.generate(
        system: split ? head : 'Follow the instructions exactly.',
        user: split ? prompt.substring(head.length).trimLeft() : prompt,
        maxOutputTokens: maxTokens * 2 + 512,
      );
      if (r.block != null || r.text.trim().isEmpty) return null;
      return r.text;
    } on GeminiError catch (e) {
      if (e.kind == GeminiErrorKind.badKey) rethrow;
      final device = await _onDevice();
      return device?.complete(prompt,
          maxTokens: maxTokens, priority: priority, head: head);
    }
  }

  @override
  Future<void> dispose() async {
    final device = await _device;
    await device?.dispose();
  }
}
