// Search suggestions from Google's autocomplete, in Japanese by default:
// the books searched for are Japanese, and so are the titles worth
// completing. Only fills the search field; what the search finds comes
// from the libraries.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;

class GoogleSuggestApi {
  GoogleSuggestApi({http.Client? client}) : _client = client;

  static const String _baseUrl =
      'https://suggestqueries.google.com/complete/search';

  final http.Client? _client;

  /// Suggestions for [query] in [language]; empty on any failure (an
  /// error never shows up as a suggestion).
  Future<List<String>> fetchSuggestions(String query,
      {String language = 'ja'}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    final url = Uri.parse(_baseUrl).replace(queryParameters: {
      // A plain JSON array: [query, [suggestions...]].
      'client': 'firefox',
      'hl': language,
      'q': cleanQuery,
    });
    try {
      final response = await (_client?.get(url) ?? http.get(url))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is List && data.length > 1 && data[1] is List) {
        return [
          for (final item in data[1] as List)
            if ('$item'.trim().isNotEmpty) '$item'.trim(),
        ];
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
