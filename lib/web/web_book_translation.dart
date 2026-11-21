// "Translate this book to the end" on a book's card on the web: the
// library's translator (the one a phone runs in the background) works on
// that book while this tab is open - there is no service behind a page.
// A book that is only on the account is fetched first.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/translation_engine.dart';
import 'package:openlib/ui/components/glossary_sheet.dart';
import 'package:openlib/web/web_library.dart';

class WebBookTranslation extends StatefulWidget {
  const WebBookTranslation({super.key, required this.book, this.sync});

  final WebBook book;

  @visibleForTesting
  final SyncService? sync;

  @override
  State<WebBookTranslation> createState() => _WebBookTranslationState();
}

class _WebBookTranslationState extends State<WebBookTranslation> {
  final _service = BookTranslationService.instance;
  late String? _fileName = widget.book.local?.getFileName();
  bool _starting = false;
  String? _problem;

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _starting = true;
      _problem = null;
    });
    try {
      if (await TranslationEngines.cacheModelId() == null) {
        if (mounted) setState(() => _problem = l10n.webTranslateNoEngine);
        return;
      }
      var file = _fileName;
      if (file == null) {
        // Only on the account: the file comes first.
        final added = await (widget.sync ?? SyncService.instance)
            .fetchBook(widget.book.remote!);
        if (added == null) throw StateError('not added');
        file = added.fileName;
        if (mounted) setState(() => _fileName = file);
      }
      await _service.start();
      await _service.prioritize(file);
    } catch (e) {
      if (mounted) setState(() => _problem = l10n.webTranslateStopped('$e'));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withAlpha(165);
    final small = TextStyle(fontSize: 12.5, color: muted);
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final file = _fileName;
        final progress = file == null ? null : _service.progress[file];
        final first = file != null && _service.priorityFile == file;
        final done = progress?.state == BookTranslationState.done;
        final error = first || progress != null ? _service.error : null;
        final problem = _problem ??
            (error != null && !first ? l10n.webTranslateStopped(error) : null);
        if (first) {
          final known = progress != null && progress.total > 0;
          return Column(
            key: const ValueKey('webTranslateRunning'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.translate_rounded,
                      size: 16, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        known
                            ? l10n.priorityTranslateProgress(
                                progress.done,
                                progress.total,
                                (progress.fraction * 100).floor())
                            : l10n.priorityTranslatePreparing,
                        key: const ValueKey('webTranslateProgress'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: muted)),
                  ),
                  TextButton(
                    key: const ValueKey('webTranslateStop'),
                    onPressed: _service.cancelPriority,
                    child: Text(l10n.translationNoticeStop),
                  ),
                ],
              ),
              // (Only when it is known how far: nothing on the web
              // animates without end.)
              if (known)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 4,
                    color: scheme.secondary,
                    backgroundColor: scheme.onSurface.withAlpha(24),
                  ),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // (A button with an icon does not let its label give way on
            // a narrow card: the row inside a plain one does.)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                key: const ValueKey('webTranslateWhole'),
                onPressed: _starting || done ? null : _start,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        done ? Icons.check_rounded : Icons.translate_rounded,
                        size: 17),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                          done
                              ? l10n.priorityTranslateDone
                              : _starting
                                  ? l10n.priorityTranslatePreparing
                                  : l10n.priorityTranslate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
            // The book's glossary, once the book is in this browser (it
            // comes with the file).
            if (file != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('webBookGlossary'),
                  onPressed: () =>
                      showGlossarySheet(context, bookFile: file),
                  icon: const Icon(Icons.menu_book_outlined, size: 17),
                  label: Text(l10n.glossaryTitle),
                ),
              ),
            const SizedBox(height: 6),
            Text(problem ?? l10n.webTranslateWholeHint,
                key: const ValueKey('webTranslateNote'),
                style: problem == null
                    ? small
                    : small.copyWith(color: scheme.error)),
          ],
        );
      },
    );
  }
}
