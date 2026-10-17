// Dart imports:
import 'dart:async';
import 'dart:convert';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import 'package:meta/meta.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/network_error.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

class BookData {
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String md5;
  final String? publisher;
  final String? info;

  /// Which catalog produced this result, for UI labelling. Null on
  /// records that predate tagging (trending rows, older caches).
  final String? source;

  BookData(
      {required this.title,
      this.author,
      this.thumbnail,
      required this.link,
      required this.md5,
      this.publisher,
      this.info,
      this.source});

  BookData copyWith({String? source, String? thumbnail}) => BookData(
        title: title,
        author: author,
        thumbnail: thumbnail ?? this.thumbnail,
        link: link,
        md5: md5,
        publisher: publisher,
        info: info,
        source: source ?? this.source,
      );
}

class BookInfoData extends BookData {
  String? mirror;
  final String? description;
  final String? format;
  bool isFastDownload;

  BookInfoData(
      {required super.title,
      required super.author,
      required super.thumbnail,
      required super.publisher,
      required super.info,
      required super.link,
      required super.md5,
      required this.format,
      required this.mirror,
      required this.description,
      this.isFastDownload = false});
}

// ====================================================================
// ANNA'S ARCHIVE SERVICE (ALL FIXES APPLIED)
// ====================================================================

class AnnasArchieve {
  AnnasArchieve({Dio? dio, InstanceManager? instanceManager})
      : dio = dio ?? Dio(),
        _instanceManager = instanceManager ?? InstanceManager();

  final Dio dio;
  final InstanceManager _instanceManager;
  final AppLogger _logger = AppLogger();

  // Optimized retry settings for faster response
  static const int maxRetriesPerInstance =
      1; // Only 1 retry per instance for speed
  static const int requestTimeoutSeconds = 8; // Shorter timeout per request
  static const int retryDelayMs = 200; // Shorter delay between retries

  Map<String, dynamic> defaultDioHeaders = {
    "user-agent":
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "accept-language": "en-US,en;q=0.9",
    "sec-ch-ua":
        '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"Linux"',
    "sec-fetch-dest": "document",
    "sec-fetch-mode": "navigate",
    "sec-fetch-site": "none",
    "sec-fetch-user": "?1",
    "upgrade-insecure-requests": "1",
  };

  // True when a response is a bot-protection interstitial rather than the
  // page we asked for.
  //
  // Two families of signal:
  //  * Cloudflare's own `cf-mitigated: challenge` header - conclusive;
  //  * the interstitials' own text. Markers that also occur on ordinary
  //    pages ("cloudflare", "please wait") only count on a status code a
  //    challenge actually uses (403/503), so a real search result page
  //    that happens to mention Cloudflare is not mistaken for a block.
  bool _isChallengeResponse(Response response) {
    if (response.headers.value('cf-mitigated')?.toLowerCase() == 'challenge') {
      _logger.warning('DDoS protection detected: cf-mitigated header',
          tag: 'AnnasArchive');
      return true;
    }

    final status = response.statusCode ?? 0;
    final body = response.data?.toString().toLowerCase() ?? '';
    if (body.isEmpty) return false;

    final title =
        RegExp(r'<title[^>]*>([^<]*)</title>').firstMatch(body)?.group(1)?.trim() ??
            '';
    const challengeTitles = [
      'just a moment',
      'ddos-guard',
      'checking your browser',
      'attention required',
    ];
    if (challengeTitles.any(title.startsWith)) {
      _logger.warning('DDoS protection detected: challenge title',
          tag: 'AnnasArchive', metadata: {'title': title});
      return true;
    }

    // Unambiguous markers of a challenge document, whatever the status.
    const hardMarkers = [
      'cf-browser-verification',
      'cf-challenge-running',
      '/cdn-cgi/challenge-platform/',
      'check.ddos-guard.net',
      'data-ddg-origin',
      '__ddg',
    ];
    for (final marker in hardMarkers) {
      if (body.contains(marker)) {
        _logger.warning('DDoS protection detected in response body',
            tag: 'AnnasArchive',
            metadata: {
              'marker': marker,
              'responseLength': body.length,
              'statusCode': status,
            });
        return true;
      }
    }

    if (status == 403 || status == 503) {
      const softMarkers = [
        'checking your browser',
        'enable javascript and cookies',
        'needs to review the security of your connection',
        'verifying you are human',
        'browser check',
        'security check',
      ];
      for (final marker in softMarkers) {
        if (body.contains(marker)) {
          _logger.warning('DDoS protection suspected (HTTP $status)',
              tag: 'AnnasArchive', metadata: {'marker': marker});
          return true;
        }
      }
    }
    return false;
  }

  /// True when [html] is an Anna's Archive document rather than some other
  /// site that answers on the same host.
  ///
  /// open-slum.org lists a few non-search hosts on its annas page - most
  /// importantly `software.annas-archive.gl`, which serves a GitLab instance.
  /// It answers `/search` with a 200 and unrelated markup, so the search
  /// parser finds nothing and the provider used to accept that as a real
  /// "no results" answer and stop, hiding the mirrors that would have
  /// worked. Every Anna's Archive page carries "Anna's Archive" in its
  /// title; a page that does not is the wrong page, not an empty result.
  bool _isAnnasArchivePage(String html) {
    final title = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.toLowerCase() ??
        '';
    return title.contains('anna') && title.contains('archive');
  }

  // Convert DioException to user-friendly NetworkError with async diagnostics
  Future<NetworkError> _handleErrorAsync(dynamic error,
      {String? responseBody, String? targetHost}) async {
    return await NetworkError.fromExceptionAsync(error,
        responseBody: responseBody, targetHost: targetHost);
  }

  // Try request with optimized retry logic - fast failure and fallback
  Future<T> _requestWithRetry<T>(
    Future<T> Function(String baseUrl) requestFn,
  ) async {
    // Anna's Archive requests must only retry across Anna's mirrors -
    // libgen/zlib mirrors 404 on AA paths and waste every retry slot.
    // The list comes from open-slum.org; down mirrors are already
    // filtered out and the easiest (least protected) mirror comes first.
    final urls =
        await _instanceManager.enabledUrls(MirrorService.annasArchive);

    if (urls.isEmpty) {
      _logger.error('No attemptable Anna\'s Archive mirror', tag: 'AnnasArchive');
      throw await _handleErrorAsync(
        Exception('No Anna\'s Archive mirror is available right now'),
      );
    }

    Exception? lastException;
    String? lastUsedHost;

    // Try each mirror - they are already ordered by open-slum.org data
    // (protection difficulty, then SLUM latency).
    for (int i = 0; i < urls.length; i++) {
      final baseUrl = urls[i];
      lastUsedHost = baseUrl;

      // Fewer retries for subsequent mirrors (they're slower)
      final retriesForThis = i == 0 ? maxRetriesPerInstance : 0;

      for (int attempt = 0; attempt <= retriesForThis; attempt++) {
        try {
          // Apply timeout to the request function
          final result = await requestFn(baseUrl).timeout(
            const Duration(seconds: requestTimeoutSeconds),
            onTimeout: () {
              throw TimeoutException(
                  "Request timed out after ${requestTimeoutSeconds}s");
            },
          );

          // Success - log which mirror worked
          _logger.debug('Request succeeded on attempt ${attempt + 1}',
              tag: 'AnnasArchive', metadata: {'mirror': baseUrl});

          return result;
        } catch (e) {
          lastException = e is Exception ? e : Exception(e.toString());

          _logger.debug('Instance failed', tag: 'AnnasArchive', metadata: {
            'mirror': baseUrl,
            'attempt': attempt + 1,
            'error': e.toString().substring(
                0, (e.toString().length > 50) ? 50 : e.toString().length),
          });

          // Short delay before retry (only if we're retrying this instance)
          if (attempt < retriesForThis) {
            await Future.delayed(const Duration(milliseconds: retryDelayMs));
          }
        }
      }
    }

    // All instances failed - throw with diagnostic info
    _logger.error('All instances failed', tag: 'AnnasArchive');

    // Throw a diagnostic NetworkError instead of the raw exception
    throw await _handleErrorAsync(
      lastException ?? Exception('All instances failed'),
      targetHost: lastUsedHost,
    );
  }

  // Plain HTTP fetch. No cookie replay: DDoS-Guard clearance is bound to the
  // browser's TLS fingerprint, so stored cookies never help here. Blocked
  // requests surface as cloudflareBlock and the webview solver takes over.
  Future<Response> _makeRequest(
    String url, {
    Map<String, String>? headers,
  }) async {
    final requestHeaders = <String, dynamic>{
      ...defaultDioHeaders,
      if (headers != null) ...headers,
    };
    // Accept any status: a Cloudflare 403 challenge must reach
    // [_isChallengeResponse] and the solver instead of dying as a raw
    // DioException before the challenge logic ever runs. Non-challenge
    // error statuses are turned back into a network failure by
    // [_ensureResponseStatus].
    return await dio.get(
      url,
      options: Options(
        headers: requestHeaders,
        validateStatus: (_) => true,
      ),
    );
  }

  /// Turns a non-challenge HTTP error status back into a network
  /// failure so [_requestWithRetry] moves on to the next mirror (and
  /// the caller never treats e.g. a 404 or a plain "link expired" 403
  /// as an empty-but-successful result).
  void _ensureResponseStatus(Response response, String url) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    _logger.warning('Anna\'s Archive returned an error status',
        tag: 'AnnasArchive',
        metadata: {'status': status, 'url': url, 'length': response.data?.toString().length ?? 0});
    throw DioException.badResponse(
      statusCode: status,
      requestOptions: response.requestOptions,
      response: response,
    );
  }

  String getMd5(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    return pathSegments.isNotEmpty ? pathSegments.last : '';
  }

  // Remove emojis, icons and non-standard characters from text
  String cleanText(String text) {
    return text
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '')
        .replaceAll(RegExp(r'🔍'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Text of an element as the browser would show it: script and style
  /// contents are skipped. Anna's Archive embeds click handlers as inline
  /// <script> tags inside the info boxes, and the html package happily
  /// includes their source in `.text`.
  String _visibleText(dom.Element? element) {
    if (element == null) return '';
    final clone = element.clone(true);
    // Detaching is enough; the cloned nodes are never attached to the tree.
    for (final node in clone.querySelectorAll('script, style')) {
      node.remove();
    }
    return clone.text.trim();
  }

  String getFormat(String info) {
    final infoLower = info.toLowerCase();
    if (infoLower.contains('pdf')) {
      return 'pdf';
    } else if (infoLower.contains('cbr')) {
      return "cbr";
    } else if (infoLower.contains('cbz')) {
      return "cbz";
    }
    return "epub";
  }

  // --------------------------------------------------------------------
  // _parser FUNCTION (Search Results - Fixed nth-of-type issue)
  // --------------------------------------------------------------------
  List<BookData> _parser(
      dynamic resData, String fileType, String currentBaseUrl) {
    var document = parse(resData.toString());

    var bookContainers =
        document.querySelectorAll('div.flex.pt-3.pb-3.border-b');

    _logger.debug('Parser started', tag: 'AnnasArchive', metadata: {
      'containerCount': bookContainers.length,
      'fileType': fileType,
      'currentBaseUrl': currentBaseUrl,
    });

    // FALLBACK: If primary selector finds nothing, try alternative selectors
    // because Anna's Archive changes its HTML structure periodically.
    if (bookContainers.isEmpty) {
      _logger.warning('Primary selector found 0 containers, trying fallbacks',
          tag: 'AnnasArchive');

      // Try 1: any link with /md5/ in href, find their parent containers
      final md5Links = document.querySelectorAll('a[href*="/md5/"]');
      _logger.debug('Found md5 links',
          tag: 'AnnasArchive', metadata: {'count': md5Links.length});

      // Try 2: divs with border-b class
      final borderDivs = document.querySelectorAll('div[class*="border-b"]');
      _logger.debug('Found border-b divs',
          tag: 'AnnasArchive', metadata: {'count': borderDivs.length});

      // Try 3: any div containing md5 link
      if (md5Links.isNotEmpty) {
        bookContainers = md5Links
            .map((link) {
              var parent = link.parent;
              while (parent != null && parent.localName != 'div') {
                parent = parent.parent;
              }
              return parent;
            })
            .whereType<dom.Element>()
            .toList();
        _logger.debug('Using fallback: md5 link parents',
            tag: 'AnnasArchive', metadata: {'count': bookContainers.length});
      }
    }

    List<BookData> bookList = [];

    for (int idx = 0; idx < bookContainers.length; idx++) {
      var container = bookContainers[idx];
      final mainLinkElement =
          container.querySelector('a.line-clamp-\\[3\\].js-vim-focus');

      // Fallback: any link with /md5/ in href
      final md5LinkElement = container.querySelector('a[href*="/md5/"]');
      final effectiveLinkElement = mainLinkElement ?? md5LinkElement;

      final thumbnailElement = container.querySelector('a[href*="/md5/"] img');

      if (effectiveLinkElement == null ||
          effectiveLinkElement.attributes['href'] == null) {
        _logger.debug('Skipped container (no mainLink)',
            tag: 'AnnasArchive', metadata: {'containerIdx': idx});
        continue;
      }

      final String title = cleanText(effectiveLinkElement.text.trim());
      final String link =
          currentBaseUrl + effectiveLinkElement.attributes['href']!;
      final String md5 = getMd5(effectiveLinkElement.attributes['href']!);
      final String? thumbnail = thumbnailElement?.attributes['src'];

      // Fix: Use sequential traversal instead of :nth-of-type
      dom.Element? authorLinkElement = effectiveLinkElement.nextElementSibling;
      dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;

      if (authorLinkElement?.attributes['href']?.startsWith('/search?q=') !=
          true) {
        authorLinkElement = null;
      }
      if (publisherLinkElement?.attributes['href']?.startsWith('/search?q=') !=
          true) {
        publisherLinkElement = null;
      }

      final String? authorRaw = authorLinkElement?.text.trim();
      final String? author = (authorRaw != null && authorRaw.contains('icon-'))
          ? cleanText(authorRaw.split(' ').skip(1).join(' ').trim())
          : (authorRaw != null ? cleanText(authorRaw) : null);

      final String? publisherRaw = publisherLinkElement?.text.trim();
      final String? publisher =
          publisherRaw != null ? cleanText(publisherRaw) : null;

      final infoElement = container.querySelector('div.text-gray-800');
      // No need for _safeParse here if we only treat info as a string
      final String? info = infoElement?.text.trim();

      // If info is null (HTML structure changed) or no filter is specified,
      // include the book. Only filter when a specific file type is requested.
      final bool hasMatchingFileType = fileType.isEmpty
          ? true
          : info?.toLowerCase().contains(fileType.toLowerCase()) == true;

      if (!hasMatchingFileType) {
        _logger.debug('Skipped container (no matching fileType)',
            tag: 'AnnasArchive',
            metadata: {
              'containerIdx': idx,
              'title':
                  title.substring(0, title.length > 50 ? 50 : title.length),
              'info': info ?? '(null)',
              'fileType': fileType,
            });
        continue;
      }

      final BookData book = BookData(
        title: title,
        author: author?.isEmpty == true ? "unknown" : author,
        thumbnail: thumbnail,
        link: link,
        md5: md5,
        publisher: publisher?.isEmpty == true ? "unknown" : publisher,
        info: info,
      );
      bookList.add(book);

      _logger.debug('Added book', tag: 'AnnasArchive', metadata: {
        'title': title.substring(0, title.length > 50 ? 50 : title.length),
        'md5': md5,
      });
    }

    _logger.info('Parser completed',
        tag: 'AnnasArchive', metadata: {'booksFound': bookList.length});
    return bookList;
  }

  /// Test-only wrappers around the private parsers so tests can verify real
  /// HTML parsing without going through the network layer.
  @visibleForTesting
  List<BookData> parser(
          dynamic resData, String fileType, String currentBaseUrl) =>
      _parser(resData, fileType, currentBaseUrl);

  @visibleForTesting
  Future<BookInfoData?> bookInfoParser(
          dynamic resData, String url, String currentBaseUrl) =>
      _bookInfoParser(resData, url, currentBaseUrl);
  // --------------------------------------------------------------------

  // --------------------------------------------------------------------
  // _bookInfoParser FUNCTION (Detail Page - Fixed 'unable to get data' error)
  // --------------------------------------------------------------------
  Future<BookInfoData?> _bookInfoParser(
      dynamic resData, String url, String currentBaseUrl) async {
    var document = parse(resData.toString());
    final main = document.querySelector('div.main-inner');
    if (main == null) return null;

    // --- Mirror Link Extraction ---
    String? mirror;

    final slowDownloadLinks =
        main.querySelectorAll('ul.list-inside a[href*="/slow_download/"]');
    if (slowDownloadLinks.isNotEmpty &&
        slowDownloadLinks.first.attributes['href'] != null) {
      mirror = currentBaseUrl + slowDownloadLinks.first.attributes['href']!;
    }
    // --------------------------------

    // --- Core Info Extraction ---

    // Title
    final titleElement = main.querySelector('div.font-semibold.text-2xl');

    // Author
    final authorLinkElement =
        main.querySelector('a[href^="/search?q="].text-base');

    // Publisher
    dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;
    if (publisherLinkElement?.localName != 'a' ||
        publisherLinkElement?.attributes['href']?.startsWith('/search?q=') !=
            true) {
      publisherLinkElement = null;
    }

    // Thumbnail
    final thumbnailElement = main.querySelector('div[id^="list_cover_"] img');

    // Info/Metadata
    final infoElement = main.querySelector('div.text-gray-800');

    // Description
    dom.Element? descriptionElement;
    final descriptionLabel = main.querySelector(
        'div.js-md5-top-box-description div.text-xs.text-gray-500.uppercase');

    if (descriptionLabel?.text.trim().toLowerCase() == 'description') {
      descriptionElement = descriptionLabel?.nextElementSibling;
    }
    String description = _visibleText(descriptionElement);

    if (titleElement == null) {
      return null;
    }

    final String title =
        cleanText(titleElement.text.trim().split('<span')[0].trim());
    final String author =
        cleanText(authorLinkElement?.text.trim() ?? "unknown");
    final String? thumbnail = thumbnailElement?.attributes['src'];

    final String publisher =
        cleanText(publisherLinkElement?.text.trim() ?? "unknown");
    // NOTE: If you extract any numeric data from the 'info' string later in your app (e.g., file size or page count)
    // and attempt to convert it to an integer or double, that's where you should use _safeParse.
    final String info = _visibleText(infoElement);

    return BookInfoData(
      title: title,
      author: author,
      thumbnail: thumbnail,
      publisher: publisher,
      info: info,
      link: url,
      md5: getMd5(url),
      format: getFormat(info),
      mirror: mirror,
      description: description,
    );
  }
  // --------------------------------------------------------------------

  String urlEncoder(
      {required String searchQuery,
      required String content,
      required String sort,
      required String fileType,
      required String language,
      required String year,
      String author = "",
      String publisher = "",
      required bool enableFilters,
      required String currentBaseUrl,
      int page = 1}) {
    // Anna's Archive accepts field-scoped terms in the query string:
    // q=author:"jrr tolkien" publisher:"harper" hobbit. Advanced
    // search fields ride the same parameter instead of inventing new
    // ones the site ignores.
    final fieldTerms = StringBuffer();
    if (author.trim().isNotEmpty) {
      final encoded = Uri.encodeQueryComponent(author.trim());
      fieldTerms.write('author:%22$encoded%22 ');
    }
    if (publisher.trim().isNotEmpty) {
      final encoded = Uri.encodeQueryComponent(publisher.trim());
      fieldTerms.write('publisher:%22$encoded%22 ');
    }
    searchQuery = (fieldTerms.toString() + searchQuery).replaceAll(" ", "+");
    // Anna's Archive paginates with &page=N after the query; page 1 is
    // the default and the parameter is omitted to keep cached challenge
    // pages matching.
    final pageParam = page > 1 ? '&page=$page' : '';
    if (!enableFilters) {
      return '$currentBaseUrl/search?q=$searchQuery$pageParam';
    }

    // Build URL with parameters in correct order for Anna's Archive
    // Working format: /search?index=&sort=&lang=nl&display=&q=query
    String url = '$currentBaseUrl/search?index=&sort=$sort';

    // Add language filter if specified (must be before q=)
    if (language.isNotEmpty) {
      url += '&lang=$language';
    }

    // Add display parameter
    url += '&display=';

    // Add search query
    url += '&q=$searchQuery';

    // Add content filter only if specified
    if (content.isNotEmpty) {
      url += '&content=$content';
    }

    // Add extension filter only if specified
    if (fileType.isNotEmpty) {
      url += '&ext=$fileType';
    }

    // Add year filter if specified
    if (year.isNotEmpty) {
      if (year == "Before 1980") {
        url += '&year_end=1979';
      } else if (year.contains('-')) {
        // Handle year ranges like "2020-2024"
        final parts = year.split('-');
        if (parts.length == 2) {
          url += '&year_from=${parts[0].trim()}&year_end=${parts[1].trim()}';
        }
      } else {
        url += '&year=$year';
      }
    }

    return '$url$pageParam';
  }

  Future<List<BookData>> searchBooks(
      {required String searchQuery,
      String content = "",
      String sort = "",
      String fileType = "",
      String language = "",
      String year = "",
      String author = "",
      String publisher = "",
      bool enableFilters = true,
      int page = 1}) async {
    _logger.info('Searching books', tag: 'AnnasArchive', metadata: {
      'query': searchQuery,
      'content': content,
      'sort': sort,
      'fileType': fileType,
      'language': language,
      'year': year,
      'author': author,
      'publisher': publisher,
      'filtersEnabled': enableFilters,
    });

    try {
      final books =
          await _requestWithRetry<List<BookData>>((currentBaseUrl) async {
        final String encodedURL = urlEncoder(
            searchQuery: searchQuery,
            content: content,
            sort: sort,
            fileType: fileType,
            language: language,
            year: year,
            author: author,
            publisher: publisher,
            enableFilters: enableFilters,
            currentBaseUrl: currentBaseUrl,
            page: page);

        // If the challenge solver already captured this page in a browser,
        // use it directly - Dio can never pass the challenge itself.
        final cached = ChallengeHtmlCache.get(encodedURL);
        if (cached != null) {
          _logger.info('Using cached challenge HTML for search',
              tag: 'AnnasArchive', metadata: {'url': encodedURL});
          return _parser(cached, fileType, currentBaseUrl);
        }

        _logger.debug('Fetching search results',
            tag: 'AnnasArchive', metadata: {'url': encodedURL});
        final response = await _makeRequest(encodedURL);

        // Log response details for debugging
        _logger
            .debug('Search response received', tag: 'AnnasArchive', metadata: {
          'statusCode': response.statusCode,
          'contentType': response.headers.value('content-type'),
          'responseLength': response.data?.toString().length ?? 0,
        });

        // Check for Cloudflare block in the response
        if (_isChallengeResponse(response)) {
          _logger.warning('Cloudflare/DDoS block detected in search response',
              tag: 'AnnasArchive');
          throw NetworkError(
            type: NetworkErrorType.cloudflareBlock,
            userMessage: "Access blocked by DDoS protection",
            solution:
                "This site is protected and blocking your access.\n\n🔧 Solutions to try:\n• Use a VPN (recommended)\n• Change your DNS to 1.1.1.1 or 8.8.8.8\n• Try a different network\n• Wait a few minutes and retry\n• Click 'Verify in Browser' to solve the captcha manually",
            technicalDetails: "DDoS challenge detected in response",
            rawResponseBody: response.data?.toString(),
            blockedUrl: encodedURL,
          );
        }

        // Not a challenge: a real error status (404, a plain "link
        // expired" 403, 5xx) must fail this attempt instead of parsing
        // into a silently-empty book list.
        _ensureResponseStatus(response, encodedURL);

        // A 200 from a host that is not Anna's Archive at all (SLUM
        // lists software.annas-archive.gl, a GitLab) must fail this
        // mirror too. Otherwise its unrelated markup parses to zero
        // books and the walk stops, reporting "no results" while the
        // mirrors that would have answered are never tried.
        if (!_isAnnasArchivePage(response.data.toString())) {
          _logger.warning('Mirror did not serve an Anna\'s Archive page',
              tag: 'AnnasArchive',
              metadata: {'url': encodedURL, 'mirror': currentBaseUrl});
          throw Exception(
              'Mirror $currentBaseUrl did not serve an Anna\'s Archive page');
        }
        return _parser(response.data, fileType, currentBaseUrl);
      });

      _logger.info('Search completed',
          tag: 'AnnasArchive', metadata: {'results': books.length});
      return books;
    } on NetworkError catch (networkErr) {
      // All mirrors are challenge-blocked. Let a real browser solve the
      // challenge and capture the page, then parse it directly. The captured
      // HTML is cached by URL, so a retry ("Try Again") parses it instantly.
      if (networkErr.type == NetworkErrorType.cloudflareBlock &&
          WebviewChallengeSolver.isSupported &&
          networkErr.blockedUrl != null) {
        _logger.info('Attempting automatic challenge solve via webview',
            tag: 'AnnasArchive');

        final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(
            networkErr.blockedUrl!);
        if (html != null && html.length > 1000) {
          _logger.info('Challenge solved, parsing results from webview HTML',
              tag: 'AnnasArchive');
          final currentBaseUrl = Uri.parse(networkErr.blockedUrl!).origin;
          return _parser(html, fileType, currentBaseUrl);
        } else {
          _logger.warning('Webview solver returned no usable HTML',
              tag: 'AnnasArchive');
        }
      }
      // Re-throw NetworkError as-is for UI to handle if solver failed or unavailable
      rethrow;
    } on DioException catch (e) {
      _logger.error('Search failed',
          tag: 'AnnasArchive', error: e.message ?? e.error);
      throw await _handleErrorAsync(e,
          responseBody: e.response?.data?.toString());
    } catch (e) {
      _logger.error('Unexpected search error',
          tag: 'AnnasArchive', error: e.toString());
      throw await _handleErrorAsync(e);
    }
  }

  Future<String?> getFastDownloadUrl(String md5, String key) async {
    _logger.info('Fetching fast download URL',
        tag: 'AnnasArchive', metadata: {'md5': md5});

    try {
      final url = await _requestWithRetry<String>((currentBaseUrl) async {
        final fastDownloadUrl =
            '$currentBaseUrl/dyn/api/fast_download.json?md5=$md5&key=$key';
        _logger.debug('Calling fast download API',
            tag: 'AnnasArchive', metadata: {'url': fastDownloadUrl});

        final response = await dio.get(fastDownloadUrl,
            options: Options(headers: defaultDioHeaders));

        if (response.statusCode == 200 || response.statusCode == 204) {
          dynamic data = response.data;
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (e) {
              _logger.warning('Failed to parse fast download JSON response',
                  tag: 'AnnasArchive', error: e.toString());
              throw Exception('Invalid JSON response');
            }
          }

          if (data is Map && data['download_url'] != null) {
            _logger.info('Fast download URL obtained', tag: 'AnnasArchive');
            return data['download_url'];
          } else {
            final errorMsg = data is Map ? data['error'] : 'Unknown error';
            _logger.warning('Fast download URL not found in response',
                tag: 'AnnasArchive', metadata: {'error': errorMsg});
            throw Exception(errorMsg ?? 'Fast download URL not found');
          }
        } else {
          _logger.error('Fast download API request failed',
              tag: 'AnnasArchive', metadata: {'status': response.statusCode});
          throw Exception('Failed to get fast download URL');
        }
      });
      return url;
    } catch (e) {
      _logger.error('Failed to get fast download URL',
          tag: 'AnnasArchive', error: e.toString());
      return null;
    }
  }

  Future<BookInfoData> bookInfo(
      {required String url, String? donationKey}) async {
    _logger.info('Fetching book info',
        tag: 'AnnasArchive', metadata: {'url': url});

    try {
      final data =
          await _requestWithRetry<BookInfoData>((currentBaseUrl) async {
        // Replace the base URL in the url parameter if it contains a different one
        String adjustedUrl = url;
        final urlParsed = Uri.parse(url);
        final currentParsed = Uri.parse(currentBaseUrl);

        // If the URL has a different host, replace it with current instance's host
        if (urlParsed.host != currentParsed.host) {
          adjustedUrl =
              '$currentBaseUrl${urlParsed.path}${urlParsed.query.isNotEmpty ? "?${urlParsed.query}" : ""}';
        }

        // If the challenge solver already captured this page in a browser,
        // use it directly - Dio can never pass the challenge itself.
        final cached = ChallengeHtmlCache.get(adjustedUrl);
        if (cached != null) {
          _logger.info('Using cached challenge HTML for bookInfo',
              tag: 'AnnasArchive', metadata: {'url': adjustedUrl});
          final data =
              await _bookInfoParser(cached, adjustedUrl, currentBaseUrl);
          if (data != null) return data;
        }

        _logger.debug('Fetching book details',
            tag: 'AnnasArchive', metadata: {'url': adjustedUrl});
        final response = await _makeRequest(adjustedUrl);

        // Check for Cloudflare block in the response
        if (_isChallengeResponse(response)) {
          _logger.warning(
              'Cloudflare/DDoS block detected in book info response',
              tag: 'AnnasArchive');
          throw NetworkError(
            type: NetworkErrorType.cloudflareBlock,
            userMessage: "Access blocked by DDoS protection",
            solution:
                "This site is protected and blocking your access.\n\n🔧 Solutions to try:\n• Use a VPN (recommended)\n• Change your DNS to 1.1.1.1 or 8.8.8.8\n• Try a different network\n• Wait a few minutes and retry\n• Click 'Verify in Browser' to solve the captcha manually",
            technicalDetails: "DDoS challenge detected in response",
            rawResponseBody: response.data?.toString(),
            blockedUrl: adjustedUrl,
          );
        }

        // Not a challenge: a real error status must fail this attempt
        // rather than be parsed into a null (handled below) or an
        // error page mistaken for book details.
        _ensureResponseStatus(response, adjustedUrl);
        BookInfoData? data =
            await _bookInfoParser(response.data, adjustedUrl, currentBaseUrl);
        if (data != null) {
          return data;
        } else {
          // Log response preview when parser fails
          final responseStr = response.data?.toString() ?? "";
          final preview = responseStr.substring(
              0, responseStr.length > 1000 ? 1000 : responseStr.length);
          _logger.error('Parser returned null - possible DDoS protection page',
              tag: 'AnnasArchive',
              metadata: {
                'url': adjustedUrl,
                'responseLength': responseStr.length,
                'statusCode': response.statusCode,
                'preview': preview,
              });

          throw NetworkError(
            type: NetworkErrorType.unknown,
            userMessage: "Unable to load book details",
            solution:
                "The book information could not be retrieved. Try again or try a different mirror in Settings.",
            technicalDetails: "Parser returned null for URL: $adjustedUrl",
            rawResponseBody: preview,
          );
        }
      });

      _logger.info('Book info retrieved successfully',
          tag: 'AnnasArchive',
          metadata: {
            'title': data.title,
            'format': data.format,
            'hasMirror': data.mirror != null,
          });
      return data;
    } on NetworkError catch (networkErr) {
      // If all instances failed with 403 and webview solver is available, try automatic solve.
      if (networkErr.type == NetworkErrorType.cloudflareBlock &&
          WebviewChallengeSolver.isSupported &&
          networkErr.blockedUrl != null) {
        _logger.info(
            'Attempting automatic challenge solve via webview for bookInfo',
            tag: 'AnnasArchive');

        final targetUrl = networkErr.blockedUrl!;
        final html =
            await WebviewChallengeSolver.fetchHtmlAfterChallenge(targetUrl);
        if (html != null && html.length > 1000) {
          _logger.info('Challenge solved, parsing bookInfo from webview HTML',
              tag: 'AnnasArchive');
          final currentBaseUrl = Uri.parse(targetUrl).origin;
          final data = await _bookInfoParser(html, targetUrl, currentBaseUrl);
          if (data != null) {
            return data;
          } else {
            // The page rendered fine but holds no book details - the md5
            // led to a search redirect. This is a dead link, not a block.
            _logger.warning('Webview HTML parsed but returned null bookInfo',
                tag: 'AnnasArchive');
            throw NetworkError(
              type: NetworkErrorType.unknown,
              userMessage: "Book not found",
              solution:
                  "The page loaded but no book details were on it. The md5 link may be outdated - try searching for the title instead.",
              technicalDetails:
                  "Parser returned null for solved page: $targetUrl",
            );
          }
        } else {
          _logger.warning('Webview solver returned no usable HTML for bookInfo',
              tag: 'AnnasArchive');
        }
      }
      // Re-throw NetworkError as-is for UI to handle if solver failed or unavailable
      rethrow;
    } on DioException catch (e) {
      _logger.error('Failed to fetch book info',
          tag: 'AnnasArchive', error: e.message ?? e.error);
      throw await _handleErrorAsync(e,
          responseBody: e.response?.data?.toString());
    } catch (e) {
      _logger.error('Unexpected book info error',
          tag: 'AnnasArchive', error: e.toString());
      throw await _handleErrorAsync(e);
    }
  }
}
