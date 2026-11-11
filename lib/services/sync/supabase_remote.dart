// SyncRemote on the owner's Supabase project (supabase/migrations/): the
// books, progress, translations, glossaries and settings tables, the
// merge RPCs and the private "books" bucket (books/<user id>/<md5>.epub,
// each with a small cover, <md5>.cover.jpg).

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Project imports:
import 'package:openlib/services/sync/sync_engine.dart';

class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this._client);

  final SupabaseClient _client;
  static const bucket = 'books';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  String _object(String md5, String format) => '$_uid/$md5.$format';
  String _cover(String md5) => '$_uid/$md5.cover.jpg';

  static DateTime _time(Object? v) => DateTime.parse('$v').toUtc();

  @override
  Future<List<RemoteBook>> books() async {
    final rows = await _client.from('books').select(
        'md5, book_id, file_name, title, author, format, size_bytes, has_file, '
        'deleted_at, publisher, description, cover_at, added_at');
    return [
      for (final r in rows)
        RemoteBook(
          md5: r['md5'] as String,
          bookId: r['book_id'] as String,
          fileName: r['file_name'] as String,
          title: (r['title'] as String?) ?? '',
          author: r['author'] as String?,
          format: (r['format'] as String?) ?? 'epub',
          sizeBytes: (r['size_bytes'] as num?)?.toInt(),
          hasFile: r['has_file'] == true,
          deleted: r['deleted_at'] != null,
          publisher: r['publisher'] as String?,
          description: r['description'] as String?,
          hasCover: r['cover_at'] != null,
          addedAt: DateTime.tryParse('${r['added_at'] ?? ''}')?.toUtc(),
        ),
    ];
  }

  @override
  Future<void> putBook(RemoteBook book) async {
    await _client.from('books').upsert({
      'md5': book.md5,
      'book_id': book.bookId,
      'file_name': book.fileName,
      'title': book.title,
      'author': book.author,
      'format': book.format,
      'size_bytes': book.sizeBytes,
      'has_file': book.hasFile,
      // Left as they are when this side does not know them.
      if (book.publisher != null) 'publisher': book.publisher,
      if (book.description != null) 'description': book.description,
      'deleted_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,md5');
  }

  @override
  Future<void> markDeleted(String md5) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('books')
        .update({'deleted_at': now, 'has_file': false, 'updated_at': now}).eq(
            'md5', md5);
  }

  @override
  Future<void> uploadBook(String md5, String format, Uint8List bytes) async {
    await _client.storage.from(bucket).uploadBinary(
          _object(md5, format),
          bytes,
          fileOptions: const FileOptions(
              upsert: true, contentType: 'application/epub+zip'),
        );
  }

  @override
  Future<Uint8List> downloadBook(String md5, String format,
      {void Function(int received, int? total)? onProgress}) async {
    final files = _client.storage.from(bucket);
    if (onProgress != null) {
      // The storage client answers only when the whole file is here; the
      // same request through Dio says how far it is.
      try {
        final response = await Dio().get<List<int>>(
          '${files.url}/object/$bucket/${_object(md5, format)}',
          options:
              Options(responseType: ResponseType.bytes, headers: files.headers),
          onReceiveProgress: (received, total) =>
              onProgress(received, total > 0 ? total : null),
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          return data is Uint8List ? data : Uint8List.fromList(data);
        }
      } on DioException catch (_) {
        // Asked again the plain way (a token renewed meanwhile).
      }
    }
    return files.download(_object(md5, format));
  }

  @override
  Future<void> removeBookFile(String md5, String format) async {
    await _client.storage
        .from(bucket)
        .remove([_object(md5, format), _cover(md5)]);
  }

  @override
  Future<void> uploadCover(String md5, Uint8List jpeg) async {
    await _client.storage.from(bucket).uploadBinary(
          _cover(md5),
          jpeg,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    await _client.from('books').update(
        {'cover_at': DateTime.now().toUtc().toIso8601String()}).eq('md5', md5);
  }

  @override
  Future<Uint8List?> downloadCover(String md5) async {
    try {
      return await _client.storage.from(bucket).download(_cover(md5));
    } on StorageException catch (_) {
      return null;
    }
  }

  @override
  Future<List<RemoteProgress>> progress() async {
    final rows = await _client
        .from('progress')
        .select('md5, position, completed, updated_at, fraction');
    return [
      for (final r in rows)
        RemoteProgress(
          md5: r['md5'] as String,
          position: (r['position'] as String?) ?? '',
          completed: r['completed'] == true,
          updatedAt: _time(r['updated_at']),
          fraction: (r['fraction'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<void> putProgress(RemoteProgress progress,
      {required String device}) async {
    final fraction = progress.fraction;
    await _client
        .rpc(fraction == null ? 'put_progress' : 'put_reading', params: {
      'p_md5': progress.md5,
      'p_position': progress.position,
      'p_completed': progress.completed,
      if (fraction != null) 'p_fraction': fraction,
      'p_device': device,
      'p_updated_at': progress.updatedAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<RemoteTranslations>> translationIndex() async {
    final rows = await _client
        .from('translations')
        .select('md5, lang, style, entry_count, updated_at');
    return [
      for (final r in rows)
        RemoteTranslations(
          md5: r['md5'] as String,
          lang: r['lang'] as String,
          style: r['style'] as String,
          count: (r['entry_count'] as num?)?.toInt() ?? 0,
          updatedAt: _time(r['updated_at']),
        ),
    ];
  }

  @override
  Future<Map<String, String>> translationEntries(
      String md5, String lang, String style) async {
    final row = await _client
        .from('translations')
        .select('entries')
        .eq('md5', md5)
        .eq('lang', lang)
        .eq('style', style)
        .maybeSingle();
    final entries = row?['entries'];
    if (entries is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in entries.entries) '$key': '$value',
    };
  }

  @override
  Future<RemoteTranslations> mergeTranslations(
      String md5, String lang, String style, Map<String, String> delta) async {
    final rows = await _client.rpc('merge_translations', params: {
      'p_md5': md5,
      'p_lang': lang,
      'p_style': style,
      'p_delta': delta,
    });
    final row = (rows as List).first as Map;
    return RemoteTranslations(
      md5: md5,
      lang: lang,
      style: style,
      count: (row['entry_count'] as num).toInt(),
      updatedAt: _time(row['updated_at']),
    );
  }

  @override
  Future<Map<String, DateTime>> glossaryIndex() async {
    final rows = await _client.from('glossaries').select('md5, updated_at');
    return {
      for (final r in rows) r['md5'] as String: _time(r['updated_at']),
    };
  }

  @override
  Future<String?> glossary(String md5) async {
    final row = await _client
        .from('glossaries')
        .select('data')
        .eq('md5', md5)
        .maybeSingle();
    return row?['data'] as String?;
  }

  @override
  Future<void> putGlossary(String md5, String data, DateTime at,
      {required String device}) async {
    await _client.rpc('put_glossary', params: {
      'p_md5': md5,
      'p_data': data,
      'p_device': device,
      'p_updated_at': at.toUtc().toIso8601String(),
    });
  }

  @override
  Future<Map<String, RemoteSetting>> settings() async {
    final rows =
        await _client.from('settings').select('name, value, updated_at');
    return {
      for (final r in rows)
        r['name'] as String: RemoteSetting(
            (r['value'] as String?) ?? '', _time(r['updated_at'])),
    };
  }

  @override
  Future<void> putSetting(String name, String value, DateTime at,
      {required String device}) async {
    await _client.rpc('put_setting', params: {
      'p_name': name,
      'p_value': value,
      'p_device': device,
      'p_updated_at': at.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> removeSetting(String name) async {
    await _client.from('settings').delete().eq('name', name);
  }
}
