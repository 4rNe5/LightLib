// Where the book page's "open in site" button points.
//
// The regression this pins: the button always built an Anna's Archive
// /md5/<id> URL. Z-Library results carry a short book id, not an md5, so
// there is no AA page for them and opening one landed on Anna's "link
// expired" error. Only a real md5 may go to Anna's Archive.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/ui/components/book_info_widget.dart'
    show openInSiteUrl;

void main() {
  const md5 = '00f8a97a0e03ac203235b306e249aa76';
  const aaBase = 'https://annas-archive.gl';

  group('openInSiteUrl', () {
    test('a Z-Library book id opens the book page, not Anna\'s Archive', () {
      // Z-Library hrefs look like /book/<id>/slug.html with a short,
      // non-hex id; there is no AA page under it.
      expect(
        openInSiteUrl(
          link: 'https://z-lib.gd/book/PqXveNwx3n/flutter.html',
          md5: 'PqXveNwx3n',
          annaArchiveBaseUrl: aaBase,
        ),
        'https://z-lib.gd/book/PqXveNwx3n/flutter.html',
      );
    });

    test('a real md5 still opens Anna\'s Archive', () {
      expect(
        openInSiteUrl(
          link: 'https://libgen.la/ads.php?md5=$md5',
          md5: md5,
          annaArchiveBaseUrl: aaBase,
        ),
        '$aaBase/md5/$md5',
      );
    });

    test('a real md5 without aa base opens its own page, not disabled', () {
      expect(
        openInSiteUrl(
          link: 'https://libgen.la/ads.php?md5=$md5',
          md5: md5,
          annaArchiveBaseUrl: null,
        ),
        'https://libgen.la/ads.php?md5=$md5',
      );
    });

    test('md5 case does not change the target', () {
      expect(
        openInSiteUrl(
          link: 'x',
          md5: md5.toUpperCase(),
          annaArchiveBaseUrl: aaBase,
        ),
        '$aaBase/md5/${md5.toUpperCase()}',
      );
    });

    test('no usable link and no md5 disables the button', () {
      expect(
        openInSiteUrl(link: '', md5: 'PqXveNwx3n', annaArchiveBaseUrl: aaBase),
        isNull,
      );
    });
  });
}
