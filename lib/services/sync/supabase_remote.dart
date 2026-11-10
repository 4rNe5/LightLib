// SyncRemote on the owner's Supabase project (supabase/migrations/): the
// books, progress and translations tables, the merge RPCs and the
// private "books" bucket (books/<user id>/<md5>.epub).

// Dart imports:
import 'dart:typed_data';

// Package imports:
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

  static DateTime _time(Object? v) => DateTime.parse('$v').toUtc();

  @override
  Future<List<RemoteBook>> books() async {
    final rows = await _client.from('books').select(
        'md5, book_id, file_name, title, author, format, size_bytes, has_file, deleted_at');
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
  Future<Uint8List> downloadBook(String md5, String format) =>
      _client.storage.from(bucket).download(_object(md5, format));

  @override
  Future<void> removeBookFile(String md5, String format) async {
    await _client.storage.from(bucket).remove([_object(md5, format)]);
  }

  @override
  Future<List<RemoteProgress>> progress() async {
    final rows = await _client
        .from('progress')
        .select('md5, position, completed, updated_at');
    return [
      for (final r in rows)
        RemoteProgress(
          md5: r['md5'] as String,
          position: (r['position'] as String?) ?? '',
          completed: r['completed'] == true,
          updatedAt: _time(r['updated_at']),
        ),
    ];
  }

  @override
  Future<void> putProgress(RemoteProgress progress,
      {required String device}) async {
    await _client.rpc('put_progress', params: {
      'p_md5': progress.md5,
      'p_position': progress.position,
      'p_completed': progress.completed,
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
}
