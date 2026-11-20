// The name of a series, asked of the reader: typed, or an existing
// series picked (the books then join it). Pops the name, or null. Shared
// by the phone's library and the web's.

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';

/// Asks what the series is called; an existing series' name can be
/// picked, and the books then join it.
class SeriesNameDialog extends StatefulWidget {
  const SeriesNameDialog(
      {super.key, required this.initial, required this.existing, this.title});

  /// The name offered: the series the books are in, or what their titles
  /// say.
  final String initial;

  /// The series there are, to join one by a tap.
  final List<String> existing;

  /// Said over the field ("Group into a series" unless given).
  final String? title;

  @override
  State<SeriesNameDialog> createState() => _State();
}

class _State extends State<SeriesNameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title ?? l10n.seriesGroup),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('seriesName'),
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l10n.seriesName),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 8),
            Text(l10n.seriesNameHint,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (widget.existing.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final name in widget.existing)
                    ActionChip(
                      key: ValueKey('seriesPick-$name'),
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _name.text = name),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
            key: const ValueKey('seriesNameSave'),
            onPressed: () => Navigator.pop(context, _name.text),
            child: Text(l10n.save)),
      ],
    );
  }
}
