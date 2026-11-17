// The requests SupabaseRemote makes itself (a part of a book's file, a
// book with its progress) say who asks: the client adds the key and the
// session's token to its own requests only, and the storage answers one
// without them 400 "Bucket not found" - the owner's library read no
// cover out of a file that way.

// Dart imports:
import 'dart:convert';
import 'dart:typed_data';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Project imports:
import 'package:openlib/services/sync/supabase_remote.dart';

class _Storage implements HttpClientAdapter {
  final List<RequestOptions> asked = [];
  final file = Uint8List.fromList(List.generate(1000, (i) => i % 251));

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    asked.add(options);
    String? header(String name) => options.headers.entries
        .where((e) => e.key.toLowerCase() == name)
        .map((e) => '${e.value}')
        .firstOrNull;
    final key = header('apikey');
    final bearer = header('authorization');
    // As the project does.
    if (key == null ||
        bearer == null ||
        !bearer.startsWith('Bearer ') ||
        bearer == 'Bearer $key') {
      return ResponseBody.fromString(
          '{"statusCode":"404","error":"Bucket not found"}', 400,
          headers: {
            'content-type': ['application/json']
          });
    }
    final range = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(header('range') ?? '');
    if (range != null) {
      final part = Uint8List.sublistView(
          file, int.parse(range.group(1)!), int.parse(range.group(2)!) + 1);
      return ResponseBody.fromBytes(part, 206);
    }
    return ResponseBody.fromBytes(file, 200, headers: {
      'content-length': ['${file.length}']
    });
  }

  @override
  void close({bool force = false}) {}
}

String _b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o)));

void main() {
  const key = 'sb_publishable_test';
  const uid = '00000000-0000-4000-8000-000000000001';
  late SupabaseClient client;
  late _Storage storage;
  late SupabaseRemote remote;
  late String token;

  setUp(() async {
    client = SupabaseClient('https://project.supabase.co', key,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    token = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({'sub': uid, 'role': 'authenticated', 'exp': exp})}.sig';
    storage = _Storage();
    remote = SupabaseRemote(client,
        apiKey: key, dio: Dio()..httpClientAdapter = storage);
  });

  tearDown(() => client.dispose());

  Future<void> signIn() => client.auth.setInitialSession(jsonEncode({
        'access_token': token,
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'refresh',
        'user': {
          'id': uid,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'owner@example.test',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-11-01T00:00:00Z',
        },
      }));

  test('a part of a file is asked for with the key and the session', () async {
    await signIn();
    final part = await remote.readBookRange('abc', 'epub', 100, 140);
    expect(part, storage.file.sublist(100, 140));
    final asked = storage.asked.single;
    expect(asked.uri.path, '/storage/v1/object/books/$uid/abc.epub');
    expect(asked.headers['apikey'], key);
    expect(asked.headers['Authorization'], 'Bearer $token');
    expect(asked.headers['Range'], 'bytes=100-139');
  });

  test('a book fetched with its progress is asked for the same way',
      () async {
    await signIn();
    final heard = <int>[];
    final bytes = await remote.downloadBook('abc', 'epub',
        onProgress: (received, total) => heard.add(received));
    expect(bytes, storage.file);
    expect(heard.last, storage.file.length);
    final asked = storage.asked.single;
    expect(asked.headers['apikey'], key);
    expect(asked.headers['Authorization'], 'Bearer $token');
  });

  test('nobody signed in: no request is made for a part', () async {
    await expectLater(
        remote.readBookRange('abc', 'epub', 0, 10), throwsStateError);
    expect(storage.asked, isEmpty);
  });

  test('a server that sends the whole file is not taken for the part',
      () async {
    await signIn();
    final whole = _Storage();
    final plain = SupabaseRemote(client,
        apiKey: key,
        dio: Dio()
          ..httpClientAdapter = whole
          ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
            o.headers.remove('Range');
            h.next(o);
          })));
    await expectLater(
        plain.readBookRange('abc', 'epub', 0, 10), throwsStateError);
  });
}
