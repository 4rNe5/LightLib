// A Google Font by name, for the reader's font choices on devices.

// Package imports:
import 'package:google_fonts/google_fonts.dart';

/// The family to draw [name] with (fetched and cached the first time), or
/// null when Google Fonts has no such font.
String? googleFontFamily(String name) {
  try {
    return GoogleFonts.getFont(name).fontFamily;
  } catch (_) {
    return null;
  }
}
