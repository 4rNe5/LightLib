// Hiding a library book's cover: a switch for the library's book sheet
// and a button for the book's page.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/hidden_covers.dart';
import 'package:openlib/state/state.dart' show libraryBooksProvider;

Future<void> _set(WidgetRef ref, String bookId, bool hidden) async {
  await HiddenCovers.instance.setHidden(bookId, hidden);
  // The home-screen widgets are drawn again from the library.
  ref.invalidate(libraryBooksProvider);
}

/// "Hide cover", with what it does.
class HideCoverSwitch extends ConsumerWidget {
  const HideCoverSwitch({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: HiddenCovers.instance,
      builder: (context, _) => SwitchListTile(
        key: const ValueKey('hideCover'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.visibility_off_outlined),
        title: Text(l10n.coverHide),
        subtitle:
            Text(l10n.coverHideHint, style: const TextStyle(fontSize: 12)),
        value: HiddenCovers.instance.isHidden(bookId),
        onChanged: (on) => _set(ref, bookId, on),
      ),
    );
  }
}

/// An app-bar button that hides or shows the cover.
class HideCoverButton extends ConsumerWidget {
  const HideCoverButton({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: HiddenCovers.instance,
      builder: (context, _) {
        final hidden = HiddenCovers.instance.isHidden(bookId);
        return IconButton(
          key: const ValueKey('hideCoverButton'),
          tooltip: hidden ? l10n.coverShow : l10n.coverHide,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          iconSize: 20,
          onPressed: () => _set(ref, bookId, !hidden),
        );
      },
    );
  }
}
