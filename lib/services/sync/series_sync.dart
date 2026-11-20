// The series the reader makes, between devices: one shared setting,
// each book's MD5 with its series ("" for a book taken out of one).
// Each device keeps the map as the account has it - books that are not
// on this device stay in it - and writes into it what the reader changes
// here (`LibrarySyncLocal`). What arrives stands for every book it
// speaks of and is applied to the books here; what only this device
// knew stays in the map and goes up with the same run.

// Dart imports:
import 'dart:convert';

/// The shared setting that carries the series.
const seriesSetting = 'series';

/// Preference: the map as the account last had it (JSON).
const seriesSharedPref = 'seriesShared';

/// [value] as a map (MD5 → series, "" = taken out); empty for anything
/// else. The value lists the books' MD5s under each series' name (and
/// under "" the ones taken out): a name is written once, not per book.
Map<String, String> decodeSeries(String? value) {
  if (value == null || value.isEmpty) return {};
  try {
    final json = jsonDecode(value);
    if (json is! Map) return {};
    return {
      for (final e in json.entries)
        if (e.value is List)
          for (final md5 in e.value as List) '$md5': '${e.key}'.trim(),
    };
  } catch (_) {
    return {};
  }
}

/// [map] as the setting's value: the same text whatever order it was
/// made in ("" when no book was ever in a series).
String encodeSeries(Map<String, String> map) {
  if (map.isEmpty) return '';
  final by = <String, List<String>>{};
  for (final e in map.entries) {
    (by[e.value] ??= []).add(e.key);
  }
  final names = by.keys.toList()..sort();
  return jsonEncode({for (final n in names) n: by[n]!..sort()});
}

/// The series of the account's books, for a list that has no rows of its
/// own for them (the web): MD5 → series, without the books taken out.
Map<String, String> sharedSeries(String? saved) => {
      for (final e in decodeSeries(saved).entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
