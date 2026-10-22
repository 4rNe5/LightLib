// Choosing the font for Korean, Japanese and Latin text.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:file_picker/file_picker.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

const _samples = {
  FontScript.korean: '그날, 내 평온했던 일상은 소리를 내며 무너져 내렸다.',
  FontScript.japanese: 'その日、俺の平穏な日常は、音を立てて崩れ去った。',
  FontScript.latin: 'That day, my peaceful life came crashing down.',
};

class ReaderFontSettingsPage extends StatefulWidget {
  const ReaderFontSettingsPage({super.key, this.fonts});

  /// Injected in tests.
  final ReaderFonts? fonts;

  @override
  State<ReaderFontSettingsPage> createState() => _ReaderFontSettingsPageState();
}

class _ReaderFontSettingsPageState extends State<ReaderFontSettingsPage> {
  late final ReaderFonts _fonts = widget.fonts ?? ReaderFonts.instance;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _fonts.addListener(_changed);
    _fonts.load();
  }

  @override
  void dispose() {
    _fonts.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: l10n.fontImport,
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      final path = files.isEmpty ? null : files.first.path;
      if (path == null) return;
      final family = await _fonts.importFontFile(path);
      await FilePicker.clearTemporaryFiles().catchError((_) => false);
      if (mounted) {
        showSnackBar(context: context, message: l10n.fontImported(family));
      }
    } catch (_) {
      if (mounted) {
        showSnackBar(context: context, message: l10n.fontImportFailed);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final titles = {
      FontScript.korean: l10n.fontKorean,
      FontScript.japanese: l10n.fontJapanese,
      FontScript.latin: l10n.fontLatin,
    };

    Widget section(FontScript script) {
      final current = _fonts.choiceFor(script);
      final options = <FontChoice>[
        FontChoice.system,
        for (final name in googleFontsByScript[script]!)
          FontChoice('google:$name'),
        for (final family in _fonts.importedFamilies)
          FontChoice('file:$family'),
      ];
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titles[script]!,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                _samples[script]!,
                style: _fonts.styleForScript(
                    script, const TextStyle(fontSize: 17, height: 1.5)),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<FontChoice>(
                key: ValueKey('font-${script.name}'),
                initialValue: options.contains(current) ? current : null,
                isExpanded: true,
                items: [
                  for (final option in options)
                    DropdownMenuItem(
                      value: option,
                      child: Text(
                        option.isSystem
                            ? l10n.fontSystem
                            : option.isFile
                                ? '${option.family} (${l10n.fontFile})'
                                : option.family,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (choice) {
                  if (choice != null) _fonts.choose(script, choice);
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text(l10n.readerFonts),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.fontsHint,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (final script in FontScript.values) section(script),
          OutlinedButton.icon(
            key: const ValueKey('importFont'),
            onPressed: _importing ? null : _import,
            icon: const Icon(Icons.font_download_outlined),
            label: Text(l10n.fontImport),
          ),
        ],
      ),
    );
  }
}
