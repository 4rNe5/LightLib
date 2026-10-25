// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/share_book.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/ui/components/book_info_widget.dart';
import 'package:openlib/ui/components/file_buttons_widget.dart';
import 'package:openlib/ui/components/hide_cover_controls.dart';
import 'package:openlib/ui/components/priority_translation_card.dart';

class BookPage extends StatelessWidget {
  const BookPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    MyLibraryDb dataBase = MyLibraryDb.instance;
    final bookInfo = dataBase.getId(id);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(AppLocalizations.of(context).appTitle),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
        actions: [
          HideCoverButton(bookId: id),
          FutureBuilder(
              future: bookInfo,
              builder: (BuildContext context, AsyncSnapshot<MyBook?> snapshot) {
                if (snapshot.hasData &&
                    snapshot.data?.title != null &&
                    snapshot.data?.link != null) {
                  return IconButton(
                    icon: Icon(
                      Icons.share_sharp,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    iconSize: 19.0,
                    onPressed: () async {
                      final outcome = await shareBook(snapshot.data!.title,
                          snapshot.data!.link, snapshot.data?.thumbnail ?? '',
                          fileName: snapshot.data?.fileName,
                          format: snapshot.data?.format);
                      if (context.mounted &&
                          outcome == ShareOutcome.pathCopied) {
                        showSnackBar(
                            context: context,
                            message: AppLocalizations.of(context)
                                .copiedBookPath);
                      }
                    },
                  );
                } else {
                  return const SizedBox.shrink();
                }
              })
        ],
      ),
      body: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          return FutureBuilder(
              future: bookInfo,
              builder: (BuildContext context, AsyncSnapshot<MyBook?> snapshot) {
                if (snapshot.hasData) {
                  final book = snapshot.data!;
                  return BookInfoWidget(
                      data: book,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FileOpenAndDeleteButtons(
                            id: book.id,
                            format: book.format!,
                            fileName: book.fileName,
                            onDelete: () {
                              Navigator.of(context).pop();
                            },
                          ),
                          if ((book.format ?? '').toLowerCase() == 'epub')
                            PriorityTranslationCard(
                                fileName: book.getFileName()),
                        ],
                      ));
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(snapshot.toString()),
                  );
                } else {
                  return Center(
                      child: SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ));
                }
              });
        },
      ),
    );
  }
}
