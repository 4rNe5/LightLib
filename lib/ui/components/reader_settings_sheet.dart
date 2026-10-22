// The reader's "Themes & Settings" sheet, laid out like Apple Books:
// text size, page themes, layout, font, then fine typography controls.

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/services/reader_settings.dart';
import 'package:openlib/ui/components/library_tiles.dart'
    show modernSurfaceTheme;
import 'package:openlib/ui/components/paged_book_view.dart' show ReaderLayout;
import 'package:openlib/ui/reader_font_settings_page.dart';

/// Opens the sheet. [script] is the script the reader is showing, whose
/// font the font row picks.
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required FontScript script,
  ReaderSettings? settings,
  ReaderFonts? fonts,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor:
        modernSurfaceTheme(Theme.of(context)).colorScheme.surfaceContainerLow,
    barrierColor: Colors.black.withAlpha(40),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => Theme(
      data: modernSurfaceTheme(Theme.of(sheetContext)),
      child: ReaderSettingsSheet(
        script: script,
        settings: settings ?? ReaderSettings.instance,
        fonts: fonts ?? ReaderFonts.instance,
      ),
    ),
  );
}

String readerThemeName(AppLocalizations l10n, ReaderThemeId theme) {
  switch (theme) {
    case ReaderThemeId.original:
      return l10n.readerThemeOriginal;
    case ReaderThemeId.paper:
      return l10n.readerThemePaper;
    case ReaderThemeId.calm:
      return l10n.readerThemeCalm;
    case ReaderThemeId.quiet:
      return l10n.readerThemeQuiet;
    case ReaderThemeId.bold:
      return l10n.readerThemeBold;
    case ReaderThemeId.night:
      return l10n.readerThemeNight;
  }
}

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.script,
    required this.settings,
    required this.fonts,
  });

  final FontScript script;
  final ReaderSettings settings;
  final ReaderFonts fonts;

  void _set(ReaderSettingsData next) => settings.update(next);

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListenableBuilder(
        listenable: Listenable.merge([settings, fonts]),
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: _content(context, settings.value),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ReaderSettingsData s) {
    final l10n = AppLocalizations.of(context);
    final appDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.readerThemesSettings,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton.filledTonal(
              tooltip: l10n.close,
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SizeControl(
          size: s.fontSize,
          onChanged: (size) => _set(s.copyWith(fontSize: size)),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.3,
          children: [
            for (final theme in ReaderThemeId.values)
              _ThemeTile(
                key: ValueKey('theme-${theme.name}'),
                name: readerThemeName(l10n, theme),
                palette: paletteFor(theme, appDark: appDark),
                selected: s.theme == theme,
                onTap: () => _set(s.copyWith(theme: theme)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Label(l10n.readerLayout),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ReaderLayout>(
            key: const ValueKey('readerLayoutSegments'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            segments: [
              ButtonSegment(
                value: ReaderLayout.scroll,
                icon: const Icon(Icons.swap_vert),
                label: Text(l10n.readerLayoutScroll),
              ),
              ButtonSegment(
                value: ReaderLayout.pagesLtr,
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text(l10n.readerLayoutPagesShort),
              ),
              ButtonSegment(
                value: ReaderLayout.pagesRtl,
                icon: Transform.flip(
                    flipX: true,
                    child: const Icon(Icons.auto_stories_outlined)),
                label: Text(l10n.readerLayoutMangaShort),
              ),
            ],
            selected: {s.layout},
            onSelectionChanged: (v) => _set(s.copyWith(layout: v.first)),
          ),
        ),
        const SizedBox(height: 16),
        _Group(children: [
          ListTile(
            key: const ValueKey('readerFontRow'),
            leading: const Icon(Icons.text_fields),
            title: Text(l10n.readerFont),
            subtitle: Text(_fontName(l10n, fonts.choiceFor(script))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickFont(context),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.readerAllFonts),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReaderFontSettingsPage(fonts: fonts))),
          ),
        ]),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _Label(l10n.readerCustomize)),
            TextButton.icon(
              key: const ValueKey('readerReset'),
              onPressed: () => _set(s.resetTypography()),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(l10n.readerReset),
            ),
          ],
        ),
        _Group(children: [
          _SliderRow(
            key: const ValueKey('lineSpacing'),
            icon: Icons.format_line_spacing,
            label: l10n.readerLineSpacing,
            value: s.lineHeight,
            min: ReaderSettingsData.minLineHeight,
            max: ReaderSettingsData.maxLineHeight,
            divisions: 12,
            display: s.lineHeight.toStringAsFixed(1),
            onChanged: (v) => _set(s.copyWith(lineHeight: v)),
          ),
          _SliderRow(
            key: const ValueKey('letterSpacing'),
            icon: Icons.format_size,
            label: l10n.readerLetterSpacing,
            value: s.letterSpacing,
            min: ReaderSettingsData.minLetterSpacing,
            max: ReaderSettingsData.maxLetterSpacing,
            divisions: 25,
            display: s.letterSpacing.toStringAsFixed(1),
            onChanged: (v) => _set(s.copyWith(letterSpacing: v)),
          ),
          _SliderRow(
            key: const ValueKey('margins'),
            icon: Icons.width_normal_outlined,
            label: l10n.readerMargins,
            value: s.margin,
            min: ReaderSettingsData.minMargin,
            max: ReaderSettingsData.maxMargin,
            divisions: 22,
            display: s.margin.round().toString(),
            onChanged: (v) => _set(s.copyWith(margin: v)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            key: const ValueKey('justify'),
            secondary: const Icon(Icons.format_align_justify),
            title: Text(l10n.readerJustify),
            value: s.justify,
            onChanged: (v) => _set(s.copyWith(justify: v)),
          ),
          SwitchListTile(
            key: const ValueKey('boldText'),
            secondary: const Icon(Icons.format_bold),
            title: Text(l10n.readerBoldText),
            value: s.boldText,
            onChanged: (v) => _set(s.copyWith(boldText: v)),
          ),
        ]),
      ],
    );
  }

  String _fontName(AppLocalizations l10n, FontChoice choice) => choice.isSystem
      ? l10n.fontSystem
      : choice.isFile
          ? '${choice.family} (${l10n.fontFile})'
          : choice.family;

  Future<void> _pickFont(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <FontChoice>[
      FontChoice.system,
      for (final name in googleFontsByScript[script]!) FontChoice('google:$name'),
      for (final family in fonts.importedFamilies) FontChoice('file:$family'),
    ];
    const samples = {
      FontScript.korean: '그날, 내 평온했던 일상은 무너져 내렸다.',
      FontScript.japanese: 'その日、俺の平穏な日常は崩れ去った。',
      FontScript.latin: 'That day, my peaceful life came crashing down.',
    };
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor:
        modernSurfaceTheme(Theme.of(context)).colorScheme.surfaceContainerLow,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
        child: ListenableBuilder(
          listenable: fonts,
          builder: (context, _) {
            final current = fonts.choiceFor(script);
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(l10n.readerFont,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final option in options)
                  ListTile(
                    key: ValueKey('fontOption-${option.id}'),
                    title: Text(
                      _fontName(l10n, option),
                      style: TextStyle(
                          fontFamily: fonts.familyOf(option),
                          fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      samples[script]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: fonts.familyOf(option), fontSize: 15),
                    ),
                    trailing: option == current
                        ? Icon(Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => fonts.choose(script, option),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600),
        ),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
}

/// Two big "A" buttons in one pill, the size between them.
class _SizeControl extends StatelessWidget {
  const _SizeControl({required this.size, required this.onChanged});

  final double size;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget half(String tooltip, double letter, double delta) => Expanded(
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              onTap: () => onChanged(size + delta),
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text('A',
                      style: TextStyle(
                          fontSize: letter,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
                ),
              ),
            ),
          ),
        );
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          half(l10n.decreaseFontSize, 15, -1),
          Container(width: 1, height: 28, color: scheme.outlineVariant),
          Semantics(
            label: l10n.readerFontSize,
            child: SizedBox(
              width: 56,
              child: Text(
                size.round().toString(),
                key: const ValueKey('readerFontSizeValue'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Container(width: 1, height: 28, color: scheme.outlineVariant),
          half(l10n.increaseFontSize, 25, 1),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    super.key,
    required this.name,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final ReaderPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                    color: scheme.primary.withAlpha(50),
                    blurRadius: 10,
                    offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Aa',
                  style: TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight:
                          palette.forceBold ? FontWeight.w900 : FontWeight.w500,
                      color: palette.text)),
              const SizedBox(height: 2),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.secondaryText)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.bodyLarge)),
              Text(display,
                  style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
