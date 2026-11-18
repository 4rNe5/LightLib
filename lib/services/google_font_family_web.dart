// The web: asking Google Fonts for a font by name pulls the table of
// every font it has into the page's script (3.4 MB of the 9 MB it was),
// and the book's page there cannot use an app font anyway. The system
// font is drawn instead.

String? googleFontFamily(String name) => null;
