// The reader's paragraph builder when translation is on.

// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:epub_view/epub_view.dart' hide Image;
// ignore: implementation_imports
import 'package:epub_view/src/data/models/paragraph.dart';
import 'package:flutter_html/flutter_html.dart';

// Project imports:
import 'package:openlib/services/translation/paragraph_text.dart';
import 'package:openlib/services/translation/reader_translation_controller.dart';

/// Per-document memo of each paragraph's translatable text (null when the
/// paragraph needs none), so scrolling does not re-walk the DOM.
class ParagraphTextMemo {
  final Map<int, String?> _texts = {};
  List<Paragraph>? _source;

  String? textAt(List<Paragraph> paragraphs, int index) {
    if (!identical(paragraphs, _source)) {
      _source = paragraphs;
      _texts.clear();
    }
    if (index < 0 || index >= paragraphs.length) return null;
    return _texts.putIfAbsent(index, () {
      final element = paragraphs[index].element;
      if (containsImage(element)) return null;
      final text = paragraphText(element);
      return shouldTranslate(text) ? text : null;
    });
  }
}

/// A chapter builder that shows each paragraph's translation in place of
/// the original once it exists. Until then the original shows, dimmed, so
/// the reader can tell what is still being translated.
///
/// Mirrors epub_view's default builder (chapter divider, padding, text
/// style, embedded images) so turning translation on changes nothing but
/// the words.
ChaptersBuilder translatingChapterBuilder({
  required ReaderTranslationController controller,
  required ParagraphTextMemo memo,
}) {
  return (
    BuildContext context,
    EpubViewBuilders builders,
    EpubBook document,
    List<EpubChapter> chapters,
    List<Paragraph> paragraphs,
    int index,
    int chapterIndex,
    int paragraphIndex,
    ExternalLinkPressed onExternalLinkPressed,
  ) {
    if (paragraphs.isEmpty) return Container();

    final options =
        (builders as EpubViewBuilders<DefaultBuilderOptions>).options;
    final element = paragraphs[index].element;
    final text = memo.textAt(paragraphs, index);

    String data = element.outerHtml;
    var pending = false;
    if (text != null) {
      controller.ensureAhead(
        index,
        textAt: (i) => memo.textAt(paragraphs, i),
        itemCount: paragraphs.length,
      );
      final translation = controller.translationOf(text);
      if (translation != null) {
        data = translatedHtml(element, translation);
      } else {
        pending = true;
      }
    }

    final padding = options.paragraphPadding as EdgeInsets?;
    final html = Html(
      data: data,
      onLinkTap: (href, _, __) {
        if (href != null) onExternalLinkPressed(href);
      },
      style: {
        'html': Style(
          padding: HtmlPaddings.only(
            top: padding?.top,
            right: padding?.right,
            bottom: padding?.bottom,
            left: padding?.left,
          ),
        ).merge(Style.fromTextStyle(options.textStyle)),
      },
      extensions: [
        TagExtension(
          tagsToExtend: {'img'},
          builder: (imageContext) {
            final url =
                (imageContext.attributes['src'] ?? '').replaceAll('../', '');
            final bytes = document.Content?.Images?[url]?.Content;
            if (bytes == null) return const SizedBox.shrink();
            return Image(image: MemoryImage(Uint8List.fromList(bytes)));
          },
        ),
      ],
    );

    return Column(
      children: <Widget>[
        if (chapterIndex >= 0 && paragraphIndex == 0)
          builders.chapterDividerBuilder(chapters[chapterIndex]),
        if (pending)
          Opacity(
            key: ValueKey('pending-$index'),
            opacity: 0.5,
            child: html,
          )
        else
          html,
      ],
    );
  };
}
