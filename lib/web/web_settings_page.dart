// Web settings: sync and the account, the translation language and
// style, Gemini (the only engine the web has), and what this browser
// keeps. A wide window shows them as a dialog over the library with its
// sections down the side; a narrow one as a page.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/local_book_import.dart' show md5FromBookId;
import 'package:openlib/services/sync/sync_service.dart';
import 'package:openlib/services/translation/translation_model_store.dart'
    show translationTargetLanguagePref;
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/ui/components/gemini_engine_section.dart';
import 'package:openlib/ui/components/sync_section.dart';
import 'package:openlib/web/browser.dart';
import 'package:openlib/web/web_library.dart' show formatBytes;

/// Opens the settings the way the window calls for.
Future<void> showWebSettings(BuildContext context) {
  if (MediaQuery.sizeOf(context).width < 900) {
    return Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WebSettingsPage()));
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 660),
        child: const WebSettingsPage(dialog: true),
      ),
    ),
  );
}

enum _Section { sync, translation, gemini, storage }

class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({super.key, this.dialog = false});

  /// Laid out inside a dialog (sections down the side).
  final bool dialog;

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<WebSettingsPage> {
  final _db = MyLibraryDb.instance;
  String _target = translationLanguages.first.code;
  bool _lightNovel = TranslationStyle.lightNovel;
  _Section _section = _Section.sync;

  @override
  void initState() {
    super.initState();
    _db
        .getPreference(translationTargetLanguagePref)
        .catchError((_) => null)
        .then((value) {
      if (value is String && mounted) {
        setState(() => _target = languageForCode(value).code);
      }
    });
  }

  Future<void> _setTarget(String code) async {
    setState(() => _target = code);
    await _db
        .savePreference(translationTargetLanguagePref, code)
        .catchError((_) {});
  }

  Future<void> _setLightNovel(bool on) async {
    setState(() => _lightNovel = on);
    TranslationStyle.lightNovel = on;
    await _db
        .savePreference(translationLightNovelStylePref, on ? 1 : 0)
        .catchError((_) {});
  }

  String _label(AppLocalizations l10n, _Section s) => switch (s) {
        _Section.sync => l10n.syncTitle,
        _Section.translation => l10n.webSectionTranslation,
        _Section.gemini => 'Gemini',
        _Section.storage => l10n.webStorage,
      };

  static IconData _icon(_Section s) => switch (s) {
        _Section.sync => Icons.sync,
        _Section.translation => Icons.translate,
        _Section.gemini => Icons.auto_awesome_outlined,
        _Section.storage => Icons.storage_outlined,
      };

  Widget _content(AppLocalizations l10n, _Section s) {
    final theme = Theme.of(context);
    switch (s) {
      case _Section.sync:
        return const SyncSection();
      case _Section.translation:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translationTargetLanguage,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: const ValueKey('webTranslationTarget'),
              initialValue: _target,
              items: [
                for (final language in translationLanguages)
                  DropdownMenuItem(
                      value: language.code, child: Text(language.nativeName)),
              ],
              onChanged: (code) {
                if (code != null) _setTarget(code);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.auto_stories_outlined),
              title: Text(l10n.translationLightNovelStyle),
              subtitle: Text(l10n.translationLightNovelStyleHint,
                  style: const TextStyle(fontSize: 12)),
              value: _lightNovel,
              onChanged: _setLightNovel,
            ),
          ],
        );
      case _Section.gemini:
        return GeminiEngineSection(onEngineChanged: () {});
      case _Section.storage:
        return const _Storage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!widget.dialog) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.settingsTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final s in _Section.values) ...[
                  if (s != _Section.values.first) const Divider(height: 32),
                  _content(l10n, s),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF121212) : Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 216,
            color: scheme.onSurface.withAlpha(10),
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                  child: Text(l10n.settingsTitle,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                for (final s in _Section.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: _section == s
                          ? scheme.onSurface.withAlpha(22)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        key: ValueKey('webSettings:${s.name}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _section = s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(_icon(s), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_label(l10n, s),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: _section == s
                                            ? FontWeight.w700
                                            : FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    key: ValueKey(_section),
                    padding: const EdgeInsets.fromLTRB(30, 30, 44, 30),
                    child: _content(l10n, _section),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    key: const ValueKey('webSettingsClose'),
                    tooltip: l10n.webClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What this browser keeps, and a way to let the downloaded books go
/// (the account still has them).
class _Storage extends StatefulWidget {
  const _Storage();

  @override
  State<_Storage> createState() => _StorageState();
}

class _StorageState extends State<_Storage> {
  int? _used;
  int _books = 0;
  bool _freeing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<List<MyBook>> _downloaded() async => [
        for (final b in await MyLibraryDb.instance.getAll())
          if ((b.format ?? '').toLowerCase() == 'epub') b,
      ];

  Future<void> _measure() async {
    final used = await Browser.storageUsed();
    final books = (await _downloaded()).length;
    if (!mounted) return;
    setState(() {
      _used = used;
      _books = books;
    });
  }

  Future<void> _free() async {
    setState(() => _freeing = true);
    final sync = SyncService.instance;
    final db = MyLibraryDb.instance;
    final md5s = await db.getSyncStates('md5:');
    var removed = 0;
    for (final book in await _downloaded()) {
      final md5 = md5FromBookId(book.id) ?? md5s['md5:${book.getFileName()}'];
      if (md5 == null) continue;
      try {
        // Only what the account safely has goes.
        if (await sync.dropLocalCopy(md5)) removed++;
      } catch (_) {}
    }
    await _measure();
    if (!mounted) return;
    setState(() => _freeing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).webStorageFreed(removed))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final small =
        TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    final used = _used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.webStorage, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
            l10n.webStorageUsed(used == null ? '—' : formatBytes(used), _books),
            key: const ValueKey('webStorageUsed')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('webStorageFree'),
          style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface),
          onPressed: _freeing || _books == 0 || !SyncService.instance.signedIn
              ? null
              : _free,
          icon: _freeing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cleaning_services_outlined, size: 18),
          label: Text(l10n.webStorageFree),
        ),
        const SizedBox(height: 6),
        Text(l10n.webStorageFreeHint, style: small),
      ],
    );
  }
}
