// Sync between this device and the owner's project: which books go
// where, which position and glossary win, how translations merge, and
// what a run reports while it goes.

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/sync/sync_engine.dart';

class _Remote implements SyncRemote {
  final bookRows = <String, RemoteBook>{};
  final files = <String, Uint8List>{};
  final progressRows = <String, RemoteProgress>{};
  final translations = <String, Map<String, String>>{};
  final translationTimes = <String, DateTime>{};
  final glossaryRows = <String, (String, DateTime)>{};
  final calls = <String>[];
  var clock = DateTime.utc(2026, 11, 9, 12);

  @override
  Future<List<RemoteBook>> books() async => bookRows.values.toList();

  @override
  Future<void> putBook(RemoteBook book) async {
    calls.add('putBook ${book.md5}');
    bookRows[book.md5] = book;
  }

  @override
  Future<void> markDeleted(String md5) async {
    calls.add('markDeleted $md5');
    final b = bookRows[md5]!;
    bookRows[md5] = RemoteBook(
        md5: md5,
        bookId: b.bookId,
        fileName: b.fileName,
        title: b.title,
        deleted: true);
  }

  @override
  Future<void> uploadBook(String md5, String format, Uint8List bytes) async {
    calls.add('upload $md5');
    files['$md5.$format'] = bytes;
  }

  @override
  Future<Uint8List> downloadBook(String md5, String format) async {
    calls.add('download $md5');
    return files['$md5.$format']!;
  }

  @override
  Future<void> removeBookFile(String md5, String format) async {
    calls.add('removeFile $md5');
    files.remove('$md5.$format');
  }

  @override
  Future<List<RemoteProgress>> progress() async => progressRows.values.toList();

  @override
  Future<void> putProgress(RemoteProgress p, {required String device}) async {
    calls.add('putProgress ${p.md5} ${p.position}');
    final old = progressRows[p.md5];
    if (old == null || old.updatedAt.isBefore(p.updatedAt)) {
      progressRows[p.md5] = p;
    }
  }

  @override
  Future<List<RemoteTranslations>> translationIndex() async => [
        for (final MapEntry(:key, :value) in translations.entries)
          RemoteTranslations(
            md5: key.split('|')[0],
            lang: key.split('|')[1],
            style: key.split('|')[2],
            count: value.length,
            updatedAt: translationTimes[key]!,
          ),
      ];

  @override
  Future<Map<String, String>> translationEntries(
          String md5, String lang, String style) async =>
      Map.of(translations[translationsKey(md5, lang, style)] ?? {});

  @override
  Future<RemoteTranslations> mergeTranslations(
      String md5, String lang, String style, Map<String, String> delta) async {
    final key = translationsKey(md5, lang, style);
    calls.add('merge $key ${delta.length}');
    (translations[key] ??= {}).addAll(delta);
    clock = clock.add(const Duration(seconds: 1));
    translationTimes[key] = clock;
    return RemoteTranslations(
        md5: md5,
        lang: lang,
        style: style,
        count: translations[key]!.length,
        updatedAt: clock);
  }

  @override
  Future<Map<String, DateTime>> glossaryIndex() async =>
      {for (final e in glossaryRows.entries) e.key: e.value.$2};

  @override
  Future<String?> glossary(String md5) async => glossaryRows[md5]?.$1;

  @override
  Future<void> putGlossary(String md5, String data, DateTime at,
      {required String device}) async {
    calls.add('putGlossary $md5 $data');
    final old = glossaryRows[md5];
    if (old == null || old.$2.isBefore(at)) glossaryRows[md5] = (data, at);
  }
}

class _Set implements LocalTranslations {
  _Set(this.local, this.path);
  final _Local local;
  final String path;

  @override
  Map<String, String> get entries => local.sets[path] ?? const {};

  @override
  int absorb(Map<String, String> other) {
    final set = local.sets[path] ??= {};
    var added = 0;
    other.forEach((k, v) {
      if (!set.containsKey(k)) {
        set[k] = v;
        added++;
      }
    });
    return added;
  }

  @override
  Future<void> save() async => local.saved.add(path);
}

class _Local implements SyncLocal {
  final held = <String, (LocalBook, Uint8List)>{};
  final positions = <String, ({String position, bool completed})>{};
  final kv = <String, String>{};
  final sets = <String, Map<String, String>>{};
  final saved = <String>[];
  final glossaries = <String, String>{};

  void addLocal(String md5, String fileName, List<int> bytes) {
    held[md5] = (
      LocalBook(id: md5, fileName: fileName, title: fileName, format: 'epub'),
      Uint8List.fromList(bytes),
    );
  }

  void read(String fileName, String position, DateTime at) {
    positions[fileName] = (position: position, completed: false);
    kv['pos:$fileName'] = '${at.millisecondsSinceEpoch}';
  }

  @override
  String get device => 'test';

  @override
  Future<List<LocalBook>> books() async => [for (final b in held.values) b.$1];

  @override
  Future<String?> md5Of(LocalBook book) async =>
      held.entries.firstWhere((e) => e.value.$1.fileName == book.fileName).key;

  @override
  Future<Uint8List?> readBook(LocalBook book) async =>
      held.values.firstWhere((b) => b.$1.fileName == book.fileName).$2;

  @override
  Future<LocalBook?> addBook(RemoteBook book, Uint8List bytes) async {
    final local = LocalBook(
        id: book.bookId,
        fileName: book.fileName,
        title: book.title,
        format: 'epub');
    held[book.md5] = (local, bytes);
    return local;
  }

  @override
  Future<void> removeBook(LocalBook book) async =>
      held.removeWhere((_, b) => b.$1.fileName == book.fileName);

  @override
  Future<({String position, bool completed})?> position(
          String fileName) async =>
      positions[fileName];

  @override
  Future<void> applyPosition(
      String fileName, String position, bool completed, DateTime at) async {
    positions[fileName] = (position: position, completed: completed);
    kv['pos:$fileName'] = '${at.millisecondsSinceEpoch}';
    kv['posSent:$fileName'] = '${at.millisecondsSinceEpoch}';
  }

  @override
  Future<Map<String, String>> state(String prefix) async => {
        for (final e in kv.entries)
          if (e.key.startsWith(prefix)) e.key: e.value
      };

  @override
  Future<void> setState(String name, String? value) async {
    if (value == null) {
      kv.remove(name);
    } else {
      kv[name] = value;
    }
  }

  @override
  List<String> get translationLanguages => const ['ko'];

  @override
  List<String> get translationStyles => const ['shared'];

  @override
  Future<String> translationPath(
          String fileName, String lang, String style) async =>
      '/tr/$fileName.$lang.$style';

  @override
  Future<Set<String>> translationPaths() async => sets.keys.toSet();

  @override
  Future<LocalTranslations> openTranslations(
          String fileName, String lang, String style) async =>
      _Set(this, await translationPath(fileName, lang, style));

  @override
  Future<String?> glossary(String fileName) async => glossaries[fileName];

  @override
  Future<void> applyGlossary(String fileName, String data, DateTime at) async {
    glossaries[fileName] = data;
    kv['gls:$fileName'] = '${at.millisecondsSinceEpoch}';
    kv['glsSent:$fileName'] = '${at.millisecondsSinceEpoch}';
  }
}

const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late _Local local;
  late _Remote remote;
  SyncEngine engine({int limit = 1 << 30}) => SyncEngine(
      local: local, remote: remote, storageLimit: limit, mergeChunk: 2);

  setUp(() {
    local = _Local();
    remote = _Remote();
  });

  group('books', () {
    test('a book only here is uploaded; one only there comes down', () async {
      local.addLocal(a, 'a.epub', [1, 2, 3]);
      remote.bookRows[b] = const RemoteBook(
          md5: b,
          bookId: b,
          fileName: 'b.epub',
          title: 'B',
          hasFile: true,
          sizeBytes: 2);
      remote.files['$b.epub'] = Uint8List.fromList([9, 9]);

      final report = await engine().run();

      expect(report.uploaded, 1);
      expect(report.downloaded, 1);
      expect(remote.files['$a.epub'], [1, 2, 3]);
      expect(remote.bookRows[a]!.hasFile, isTrue);
      expect(local.held[b]!.$2, [9, 9]);
      expect(local.kv.keys, containsAll(['seen:$a', 'seen:$b']));
    });

    test('a second run with nothing new sends and fetches nothing', () async {
      local.addLocal(a, 'a.epub', [1]);
      await engine().run();
      remote.calls.clear();
      final report = await engine().run();
      expect(report.uploaded + report.downloaded, 0);
      expect(remote.calls, isEmpty);
    });

    test('deleted here after a sync: deleted there too', () async {
      local.addLocal(a, 'a.epub', [1]);
      await engine().run();
      local.held.remove(a);

      final report = await engine().run();

      expect(report.removedThere, 1);
      expect(remote.bookRows[a]!.deleted, isTrue);
      expect(remote.files.containsKey('$a.epub'), isFalse);
      expect(local.kv.containsKey('seen:$a'), isFalse);
    });

    test('many missing at once (a lost book folder): nothing deleted',
        () async {
      const md5s = ['1', '2', '3', '4', '5'];
      for (final d in md5s) {
        local.addLocal(d * 32, '$d.epub', [1]);
      }
      await engine().run();
      local.held.clear();

      final report = await engine().run();

      expect(report.deletesHeld, 5);
      expect(report.removedThere, 0);
      expect(remote.bookRows.values.where((b) => b.deleted), isEmpty);
      // They come back down instead of staying lost.
      expect(report.downloaded, 0);
    });

    test('deleted elsewhere: removed here', () async {
      local.addLocal(a, 'a.epub', [1]);
      await engine().run();
      await remote.markDeleted(a);

      final report = await engine().run();

      expect(report.removedHere, 1);
      expect(local.held, isEmpty);
    });

    test('a deleted book added again here (never seen) goes up again',
        () async {
      remote.bookRows[a] = const RemoteBook(
          md5: a, bookId: a, fileName: 'a.epub', title: 'A', deleted: true);
      local.addLocal(a, 'a.epub', [7]);

      final report = await engine().run();

      expect(report.uploaded, 1);
      expect(local.held.containsKey(a), isTrue);
      expect(remote.bookRows[a]!.deleted, isFalse);
    });

    test('over the storage limit: kept here, reported', () async {
      local.addLocal(a, 'a.epub', List.filled(10, 1));
      final report = await engine(limit: 5).run();
      expect(report.uploaded, 0);
      expect(report.skippedForSpace, 1);
      expect(remote.files, isEmpty);
    });
  });

  group('positions', () {
    final early = DateTime.utc(2026, 11, 9, 10);
    final late = DateTime.utc(2026, 11, 9, 11);

    test('read here last: sent', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.read('a.epub', 'foliate:here', late);
      remote.progressRows[a] = RemoteProgress(
          md5: a,
          position: 'foliate:there',
          completed: false,
          updatedAt: early);

      final report = await engine().run(quick: true);

      expect(report.positionsSent, 1);
      expect(remote.progressRows[a]!.position, 'foliate:here');
      expect(local.kv['posSent:a.epub'], '${late.millisecondsSinceEpoch}');
    });

    test('read elsewhere last: taken here', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.read('a.epub', 'foliate:here', early);
      remote.progressRows[a] = RemoteProgress(
          md5: a, position: 'foliate:there', completed: false, updatedAt: late);

      final report = await engine().run(quick: true);

      expect(report.positionsReceived, 1);
      expect(local.positions['a.epub']!.position, 'foliate:there');
      // Taken, not a change to send back.
      remote.calls.clear();
      await engine().run(quick: true);
      expect(remote.calls.where((c) => c.startsWith('putProgress')), isEmpty);
    });

    test('saved before sync (no time): up when the remote has none', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.positions['a.epub'] = (position: 'foliate:old', completed: false);

      final report = await engine().run(quick: true);

      expect(report.positionsSent, 1);
      expect(remote.progressRows[a]!.position, 'foliate:old');
      expect(remote.progressRows[a]!.updatedAt, unknownAge);
      // Sent once, not again.
      remote.calls.clear();
      await engine().run(quick: true);
      expect(remote.calls.where((c) => c.startsWith('putProgress')), isEmpty);
    });

    test('saved before sync (no time): the remote one wins', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.positions['a.epub'] = (position: 'foliate:old', completed: false);
      remote.progressRows[a] = RemoteProgress(
          md5: a, position: 'foliate:there', completed: true, updatedAt: early);

      final report = await engine().run(quick: true);

      expect(report.positionsReceived, 1);
      expect(local.positions['a.epub'],
          (position: 'foliate:there', completed: true));
      expect(remote.calls.where((c) => c.startsWith('putProgress')), isEmpty);
    });

    test('an unknown-age position from elsewhere loses to one read here',
        () async {
      local.addLocal(a, 'a.epub', [1]);
      local.read('a.epub', 'foliate:here', early);
      remote.progressRows[a] = RemoteProgress(
          md5: a,
          position: 'foliate:old',
          completed: false,
          updatedAt: unknownAge);

      await engine().run(quick: true);

      expect(remote.progressRows[a]!.position, 'foliate:here');
      expect(local.positions['a.epub']!.position, 'foliate:here');
    });

    test('a quick run: books are neither sent nor fetched', () async {
      local.addLocal(a, 'a.epub', [1]);
      await engine().run(quick: true);
      expect(remote.calls.where((c) => c.startsWith('upload')), isEmpty);
    });
  });

  group('translations', () {
    test('union: each side gets what the other made, deltas only', () async {
      local.addLocal(a, 'a.epub', [1]);
      const path = '/tr/a.epub.ko.shared';
      local.sets[path] = {'h1': 'mine', 'h2': 'both-mine'};
      remote.translations['$a|ko|shared'] = {
        'h2': 'both-theirs',
        'h3': 'theirs'
      };
      remote.translationTimes['$a|ko|shared'] = DateTime.utc(2026, 11, 9, 9);

      final report = await engine().run();

      // This device keeps its own h2 and gains h3.
      expect(
          local.sets[path], {'h1': 'mine', 'h2': 'both-mine', 'h3': 'theirs'});
      expect(report.translationsReceived, 1);
      // The remote gets h1 and this device's h2 (2 entries, one request).
      expect(report.translationsSent, 2);
      expect(remote.translations['$a|ko|shared'],
          {'h1': 'mine', 'h2': 'both-mine', 'h3': 'theirs'});
      expect(local.saved, [path]);
      expect(local.kv['trinit'], '1');
    });

    test('unchanged on both sides: not fetched again', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.sets['/tr/a.epub.ko.shared'] = {'h1': 'x'};
      await engine().run();
      remote.calls.clear();
      local.saved.clear();

      await engine().run();

      expect(remote.calls.where((c) => c.startsWith('merge')), isEmpty);
      expect(local.saved, isEmpty);
    });

    test('changed here since (marked dirty): only the new ones go', () async {
      local.addLocal(a, 'a.epub', [1]);
      const path = '/tr/a.epub.ko.shared';
      local.sets[path] = {'h1': 'x'};
      await engine().run();
      local.sets[path]!['h2'] = 'y';
      local.kv['trdirty:$path'] = '1';
      remote.calls.clear();

      final report = await engine().run();

      expect(report.translationsSent, 1);
      expect(remote.calls.where((c) => c.startsWith('merge')).toList(),
          ['merge $a|ko|shared 1']);
      expect(local.kv.containsKey('trdirty:$path'), isFalse);
    });

    test('large deltas go in chunks', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.sets['/tr/a.epub.ko.shared'] = {
        for (var i = 0; i < 5; i++) 'h$i': 't$i'
      };
      await engine().run();
      expect(remote.calls.where((c) => c.startsWith('merge')).length, 3);
      expect(remote.translations['$a|ko|shared']!.length, 5);
    });
  });

  group('a book that comes down', () {
    test('brings its position, translations and glossary with it', () async {
      remote.bookRows[b] = const RemoteBook(
          md5: b, bookId: b, fileName: 'b.epub', title: 'B', hasFile: true);
      remote.files['$b.epub'] = Uint8List.fromList([9]);
      remote.progressRows[b] = RemoteProgress(
          md5: b,
          position: 'foliate:p',
          completed: false,
          updatedAt: DateTime.utc(2026, 11, 9, 10));
      remote.translations['$b|ko|shared'] = {'h1': '번역'};
      remote.translationTimes['$b|ko|shared'] = DateTime.utc(2026, 11, 9, 10);
      remote.glossaryRows[b] =
          ('{"entries":[]}', DateTime.utc(2026, 11, 9, 10));
      final events = <String>[];
      final report = await SyncEngine(
        local: local,
        remote: remote,
        onLocalChange: () => events.add(
            'book here, translations ${local.sets['/tr/b.epub.ko.shared']}'),
      ).run();

      expect(report.downloaded, 1);
      expect(local.positions['b.epub']!.position, 'foliate:p');
      expect(local.sets['/tr/b.epub.ko.shared'], {'h1': '번역'});
      expect(local.glossaries['b.epub'], '{"entries":[]}');
      // Whole before the library is told it is there.
      expect(events, ['book here, translations {h1: 번역}']);
      // Fetched once: the run's own pass does not fetch them again.
      expect(report.translationsReceived, 1);
    });

    test('several at once, all of them', () async {
      for (final d in ['1', '2', '3', '4', '5']) {
        final md5 = d * 32;
        remote.bookRows[md5] = RemoteBook(
            md5: md5,
            bookId: md5,
            fileName: '$d.epub',
            title: d,
            hasFile: true);
        remote.files['$md5.epub'] = Uint8List.fromList([int.parse(d)]);
      }
      final report =
          await SyncEngine(local: local, remote: remote, transfers: 3).run();
      expect(report.downloaded, 5);
      expect(local.held.length, 5);
    });
  });

  group('glossaries', () {
    test('made here before sync: up when the remote has none', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.glossaries['a.epub'] = 'mine';
      final report = await engine().run(quick: true);
      expect(report.glossariesSent, 1);
      expect(remote.glossaryRows[a]!.$1, 'mine');
    });

    test('changed here last: up; changed there last: taken', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.glossaries['a.epub'] = 'mine';
      local.kv['gls:a.epub'] =
          '${DateTime.utc(2026, 11, 9, 11).millisecondsSinceEpoch}';
      remote.glossaryRows[a] = ('theirs', DateTime.utc(2026, 11, 9, 10));

      await engine().run(quick: true);
      expect(remote.glossaryRows[a]!.$1, 'mine');

      remote.glossaryRows[a] = ('newer', DateTime.utc(2026, 11, 9, 12));
      final report = await engine().run(quick: true);
      expect(report.glossariesReceived, 1);
      expect(local.glossaries['a.epub'], 'newer');
      // Taken, not sent back.
      remote.calls.clear();
      await engine().run(quick: true);
      expect(remote.calls.where((c) => c.startsWith('putGlossary')), isEmpty);
    });
  });

  group('one book (opened)', () {
    test('its position and translations both ways, nothing else', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.addLocal(b, 'b.epub', [2]);
      remote.translations['$a|ko|shared'] = {'h1': 'x'};
      remote.translationTimes['$a|ko|shared'] = DateTime.utc(2026, 11, 9, 10);
      remote.translations['$b|ko|shared'] = {'h2': 'y'};
      remote.translationTimes['$b|ko|shared'] = DateTime.utc(2026, 11, 9, 10);

      final report = await engine().runBook('a.epub');

      expect(report!.translationsReceived, 1);
      expect(local.sets['/tr/a.epub.ko.shared'], {'h1': 'x'});
      expect(local.sets.containsKey('/tr/b.epub.ko.shared'), isFalse);
      expect(remote.calls.where((c) => c.startsWith('upload')), isEmpty);
      expect(await engine().runBook('missing.epub'), isNull);
    });
  });

  group('progress', () {
    test('says each stage with its count', () async {
      local.addLocal(a, 'a.epub', [1]);
      local.sets['/tr/a.epub.ko.shared'] = {'h1': 'x'};
      remote.bookRows[b] = const RemoteBook(
          md5: b, bookId: b, fileName: 'b.epub', title: 'B', hasFile: true);
      remote.files['$b.epub'] = Uint8List.fromList([9]);
      final seen = <String>[];
      await SyncEngine(
        local: local,
        remote: remote,
        onProgress: (p) => seen.add('${p.stage.name} ${p.done}/${p.total}'),
      ).run();
      expect(seen, [
        'checking 0/0',
        'translations 0/1',
        'translations 1/1',
        'uploading 0/1',
        'downloading 0/1',
        'downloading 1/1',
      ]);
    });

    test('a run with nothing to move reports no transfers', () async {
      final seen = <SyncProgress>[];
      await SyncEngine(local: local, remote: remote, onProgress: seen.add)
          .run();
      expect(seen.where((p) => p.transfers), isEmpty);
    });
  });
}
