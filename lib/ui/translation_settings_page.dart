// Settings for on-device translation: target language and model files.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/translation/book_translation_service.dart';
import 'package:openlib/services/translation/translation_cache.dart';
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translator.dart';
import 'package:openlib/services/translation/translation_models.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

String formatGigabytes(int bytes) => '${(bytes / 1e9).toStringAsFixed(2)} GB';

class TranslationSettingsPage extends StatefulWidget {
  const TranslationSettingsPage({super.key, this.store, this.database});

  /// Injected in tests.
  final TranslationModelStore? store;
  final MyLibraryDb? database;

  @override
  State<TranslationSettingsPage> createState() =>
      _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  late final TranslationModelStore _store =
      widget.store ?? TranslationModelStore.instance;
  late final MyLibraryDb _db = widget.database ?? MyLibraryDb.instance;

  List<InstalledModel> _installed = const [];
  InstalledModel? _active;
  String _target = translationLanguages.first.code;
  bool _importing = false;
  bool _lightNovelStyle = TranslationStyle.lightNovel;

  @override
  void initState() {
    super.initState();
    _store.addListener(_reload);
    _reload();
    _db
        .getPreference(translationTargetLanguagePref)
        .catchError((_) => null)
        .then((value) {
      if (value is String && mounted) {
        setState(() => _target = languageForCode(value).code);
      }
    });
  }

  @override
  void dispose() {
    _store.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final installed = await _store.installed();
    final active = await _store.activeModel(database: _db);
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _active = active;
    });
  }

  /// Light-novel style on/off. Each style keeps its own translations, so
  /// the reader and the library translator pick up the other set.
  Future<void> _setLightNovelStyle(bool on) async {
    setState(() => _lightNovelStyle = on);
    TranslationStyle.lightNovel = on;
    await _db
        .savePreference(translationLightNovelStylePref, on ? 1 : 0)
        .catchError((_) {});
    BookTranslationService.instance.scanSoon();
  }

  Future<void> _setTarget(String code) async {
    setState(() => _target = code);
    await _db.savePreference(translationTargetLanguagePref, code);
    _restartTranslation();
  }

  /// A new model or language: the loaded engine goes, and the background
  /// translator starts over with the new settings.
  Future<void> _restartTranslation() async {
    await SharedTranslationEngine.instance.reset();
    BookTranslationService.instance.scanSoon();
  }

  Future<void> _use(String fileName) async {
    await _store.select(fileName, database: _db);
    await _restartTranslation();
  }

  /// Null clears the override: the format is detected again.
  Future<void> _setPromptFormat(
      String fileName, TranslationPromptFormat? format) async {
    final next = Map.of(TranslationPromptFormats.overrides);
    if (format == null) {
      next.remove(fileName);
    } else {
      next[fileName] = format;
    }
    setState(() => TranslationPromptFormats.overrides = next);
    await _db
        .savePreference(TranslationPromptFormats.pref,
            TranslationPromptFormats.encode(next))
        .catchError((_) {});
    // Cached translations are kept per format; the reader and the
    // background translator pick the new one up.
    await _restartTranslation();
  }

  String _formatLabel(AppLocalizations l10n, TranslationPromptFormat f) {
    switch (f) {
      case TranslationPromptFormat.general:
        return l10n.promptFormatGeneral;
      case TranslationPromptFormat.hyMt:
        return l10n.promptFormatHyMt;
      case TranslationPromptFormat.jaKoDialogue:
        return l10n.promptFormatJaKo;
    }
  }

  /// GPU first, or the CPU only (the GPU stays free for the screen).
  Widget _devicePicker(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: DropdownButtonFormField<bool>(
        key: const ValueKey('translationDevice'),
        initialValue: SharedTranslationEngine.cpuOnly,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.translationDevice,
          helperText: l10n.translationDeviceHint,
          helperMaxLines: 3,
        ),
        items: [
          DropdownMenuItem(
              value: false,
              child: Text(l10n.translationDeviceAuto,
                  overflow: TextOverflow.ellipsis)),
          DropdownMenuItem(
              value: true,
              child: Text(l10n.translationDeviceCpu,
                  overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (cpu) async {
          if (cpu == null) return;
          // Choosing again also gives the GPU another chance after a
          // stall made this model run on the CPU.
          final active = _active?.fileName;
          if (active != null) await LocalLlmTranslator.clearGpuStall(active);
          if (cpu == SharedTranslationEngine.cpuOnly) {
            await _restartTranslation();
            return;
          }
          SharedTranslationEngine.cpuOnly = cpu;
          setState(() {});
          await _db
              .savePreference(translationDevicePref, cpu ? 'cpu' : 'auto')
              .catchError((_) {});
          await _restartTranslation();
        },
      ),
    );
  }

  Widget _promptFormatPicker(AppLocalizations l10n, InstalledModel model) {
    final detected = detectPromptFormat(model.fileName);
    final override = TranslationPromptFormats.overrides[model.fileName];
    final target = languageForCode(_target).englishName;
    final effective = override ?? detected;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<TranslationPromptFormat?>(
            key: const ValueKey('promptFormat'),
            initialValue: override,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.translationPromptFormat,
              helperText: l10n.translationPromptFormatHint,
              helperMaxLines: 3,
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(l10n.promptFormatAuto(_formatLabel(l10n, detected)),
                    overflow: TextOverflow.ellipsis),
              ),
              for (final f in TranslationPromptFormat.values)
                DropdownMenuItem(
                    value: f,
                    child: Text(_formatLabel(l10n, f),
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (f) => _setPromptFormat(model.fileName, f),
          ),
          if (!effective.supportsTarget(target))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l10n.promptFormatKoreanOnly,
                  key: const ValueKey('promptFormatKoreanOnly'),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDownload(TranslationModelPreset preset) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(preset.name),
        content: Text(
            l10n.translationDownloadConfirm(formatGigabytes(preset.sizeBytes))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.translationDownload),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.download(preset);
      if (!_store.downloads.containsKey(preset.id)) {
        await _restartTranslation();
      }
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: l10n.translationImportModel,
        type: FileType.any,
      );
      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;
      if (runtimeForFile(path) == null) {
        if (mounted) {
          showSnackBar(context: context, message: l10n.translationNotAModel);
        }
        return;
      }
      final model = await _store.importFile(path);
      await _use(model.fileName);
      // The picker leaves its own copy in the cache; a model is gigabytes.
      await FilePicker.clearTemporaryFiles().catchError((_) => false);
      if (mounted) {
        showSnackBar(context: context, message: l10n.translationImported);
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context: context, message: l10n.translationImportFailed);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(InstalledModel model) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(model.displayName),
        content: Text(l10n.translationDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(model.fileName);
      await _restartTranslation();
    }
  }

  Future<void> _clearCache() async {
    final l10n = AppLocalizations.of(context);
    for (final dir in [
      await TranslationCache.bookFolderDirectory(),
      Directory(p.join(
          (await getApplicationSupportDirectory()).path, 'translations')),
    ]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await _restartTranslation();
    if (mounted) {
      showSnackBar(context: context, message: l10n.translationCacheCleared);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final installedNames = _installed.map((m) => m.fileName).toSet();
    final imported =
        _installed.where((m) => m.preset == null).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text(l10n.translationSettingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.translationTargetLanguage,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: const ValueKey('translationTarget'),
            initialValue: _target,
            items: [
              for (final language in translationLanguages)
                DropdownMenuItem(
                  value: language.code,
                  child: Text(language.nativeName),
                ),
            ],
            onChanged: (code) {
              if (code != null) _setTarget(code);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('lightNovelStyle'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.auto_stories_outlined),
            title: Text(l10n.translationLightNovelStyle),
            subtitle: Text(l10n.translationLightNovelStyleHint,
                style: const TextStyle(fontSize: 12)),
            value: _lightNovelStyle,
            onChanged: _setLightNovelStyle,
          ),
          const SizedBox(height: 12),
          Text(l10n.translationModels,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(l10n.translationModelsHint,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final preset in translationModelPresets)
            _ModelCard(
              key: ValueKey('preset-${preset.id}'),
              title: preset.name,
              subtitle:
                  '${formatGigabytes(preset.sizeBytes)} · ${preset.license}'
                  '${preset == gemma4E4bLiteRt ? ' · ${l10n.translationRecommended} · ${l10n.translationNeedsRam(8)}' : ''}'
                  '${preset == gemma4E2bLiteRt ? ' · ${l10n.translationFaster}' : ''}',
              installed: installedNames.contains(preset.fileName),
              active: _active?.fileName == preset.fileName,
              download: _store.downloads[preset.id],
              onDownload: () => _confirmDownload(preset),
              onCancel: () => _store.cancelDownload(preset.id),
              onUse: () => _use(preset.fileName),
              onDelete: () => _delete(
                  _installed.firstWhere((m) => m.fileName == preset.fileName)),
            ),
          for (final model in imported)
            _ModelCard(
              key: ValueKey('imported-${model.fileName}'),
              title: model.fileName,
              subtitle:
                  '${formatGigabytes(model.sizeBytes)} · ${model.runtime == TranslationRuntime.liteRtLm ? 'LiteRT-LM' : 'llama.cpp'}',
              installed: true,
              active: _active?.fileName == model.fileName,
              onUse: () => _use(model.fileName),
              onDelete: () => _delete(model),
            ),
          if (_active != null) _promptFormatPicker(l10n, _active!),
          if (_active?.runtime == TranslationRuntime.liteRtLm)
            _devicePicker(l10n),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('importModel'),
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_open_outlined),
            label: Text(l10n.translationImportModel),
          ),
          const SizedBox(height: 20),
          const _LibraryTranslationSection(),
          const SizedBox(height: 12),
          Text(l10n.translationBatteryNote,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _clearCache,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(l10n.translationClearCache),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.installed,
    required this.active,
    this.download,
    this.onDownload,
    this.onCancel,
    required this.onUse,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final bool installed;
  final bool active;
  final ModelDownloadState? download;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = download;
    final busy = state != null && state.phase != ModelDownloadPhase.failed;

    Widget trailing;
    if (busy) {
      trailing = IconButton(
        tooltip: l10n.cancel,
        icon: const Icon(Icons.close),
        onPressed:
            state.phase == ModelDownloadPhase.downloading ? onCancel : null,
      );
    } else if (installed) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            Chip(
              label: Text(l10n.translationInUse),
              visualDensity: VisualDensity.compact,
            )
          else
            TextButton(onPressed: onUse, child: Text(l10n.translationUse)),
          IconButton(
            tooltip: l10n.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: onDownload,
        child: Text(state?.phase == ModelDownloadPhase.failed
            ? l10n.retry
            : l10n.translationDownload),
      );
    }

    String? progressText;
    if (state != null) {
      switch (state.phase) {
        case ModelDownloadPhase.downloading:
          final pct = ((state.fraction ?? 0) * 100).toStringAsFixed(0);
          progressText =
              '$pct% · ${formatGigabytes(state.receivedBytes)} / ${formatGigabytes(state.totalBytes)}';
        case ModelDownloadPhase.verifying:
          progressText = l10n.translationVerifying;
        case ModelDownloadPhase.failed:
          progressText = l10n.translationDownloadFailed(state.error ?? '');
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
            if (state != null) ...[
              const SizedBox(height: 8),
              if (busy)
                LinearProgressIndicator(
                  value: state.phase == ModelDownloadPhase.verifying
                      ? null
                      : state.fraction,
                ),
              const SizedBox(height: 4),
              Text(
                progressText ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: state.phase == ModelDownloadPhase.failed
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The background library translation switch and each book's progress.
class _LibraryTranslationSection extends StatelessWidget {
  const _LibraryTranslationSection();

  static String _waitLabel(AppLocalizations l10n, BookTranslationWait wait) =>
      switch (wait) {
        BookTranslationWait.none => '',
        BookTranslationWait.reading => l10n.translationWaitReading,
        BookTranslationWait.appClosed => l10n.translationWaitAppClosed,
        BookTranslationWait.warm => l10n.translationWaitWarm,
        BookTranslationWait.batteryLow => l10n.translationWaitBattery,
        BookTranslationWait.powerSave => l10n.translationWaitPowerSave,
        BookTranslationWait.needsCharger => l10n.translationWaitCharger,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final service = BookTranslationService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final books = service.progress.values.toList()
          ..sort((a, b) => a.title.compareTo(b.title));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('autoTranslateLibrary'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.translationAutoLibrary),
              subtitle: Text(l10n.translationAutoLibraryHint,
                  style: const TextStyle(fontSize: 12)),
              value: service.enabled,
              onChanged: (on) async {
                // The progress notification needs the permission
                // (Android 13+); without it the work still runs.
                if (on && Platform.isAndroid) {
                  await Permission.notification
                      .request()
                      .catchError((_) => PermissionStatus.denied);
                }
                await service.setEnabled(on);
              },
            ),
            if (service.enabled)
              SwitchListTile(
                key: const ValueKey('translateLibraryChargingOnly'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.translationChargingOnly),
                subtitle: Text(l10n.translationChargingOnlyHint,
                    style: const TextStyle(fontSize: 12)),
                value: service.chargingOnly,
                onChanged: service.setChargingOnly,
              ),
            if (service.enabled &&
                service.running &&
                service.wait != BookTranslationWait.none)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_outline,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_waitLabel(l10n, service.wait),
                          key: const ValueKey('libraryTranslationWait'),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            if (service.error != null)
              Text(l10n.translationFailed,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            for (final book in books)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text(
                          book.state == BookTranslationState.done
                              ? l10n.translationBookDone
                              : '${(book.fraction * 100).toStringAsFixed(0)}% · ${book.done}/${book.total}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: book.fraction,
                      minHeight: 3,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
