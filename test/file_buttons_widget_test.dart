// Z-Library reports "EPUB" and "PDF" in its metadata. These must route
// to the built-in viewers rather than Android's external app chooser.
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/file_buttons_widget.dart'
    show BookOpenTarget, bookOpenTargetForFormat;

void main() {
  group('bookOpenTargetForFormat', () {
    test('uppercase and padded EPUB uses the internal reader route', () {
      expect(bookOpenTargetForFormat('EPUB'), BookOpenTarget.epub);
      expect(bookOpenTargetForFormat(' epub '), BookOpenTarget.epub);
      expect(bookOpenTargetForFormat('ePuB'), BookOpenTarget.epub);
    });

    test('uppercase and padded PDF uses the internal reader route', () {
      expect(bookOpenTargetForFormat('PDF'), BookOpenTarget.pdf);
      expect(bookOpenTargetForFormat(' Pdf '), BookOpenTarget.pdf);
    });

    test('unsupported formats keep the external app route', () {
      expect(bookOpenTargetForFormat('CBR'), BookOpenTarget.external);
      expect(bookOpenTargetForFormat('cbz'), BookOpenTarget.external);
      expect(bookOpenTargetForFormat('mobi'), BookOpenTarget.external);
    });
  });
}
