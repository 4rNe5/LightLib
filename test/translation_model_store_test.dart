// Model files: download with resume and checksum, import, selection.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/translation_model_store.dart';
import 'package:openlib/services/translation/translation_models.dart';

void main() {
  late Directory dir;
  late HttpServer server;
  late List<int> body;
  final requests = <String?>[];
  var dropAfter = -1; // close the first response after N bytes

  final store = TranslationModelStore.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tmodels');
    store.directoryProvider = () async => dir;
    body = List<int>.generate(300000, (i) => (i * 31) % 251);
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value('range');
      requests.add(range);
      var start = 0;
      if (range != null) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
        req.response.headers.set(
            'content-range', 'bytes $start-${body.length - 1}/${body.length}');
      }
      final slice = body.sublist(start);
      if (dropAfter >= 0) {
        // Promise the whole file, send part of it, then drop the
        // connection - a transfer cut off mid-way.
        final cut = dropAfter;
        dropAfter = -1;
        req.response.headers.contentLength = slice.length;
        final socket = await req.response.detachSocket(writeHeaders: true);
        socket.add(slice.sublist(0, cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      req.response.add(slice);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  TranslationModelPreset presetFor(List<int> content, {String? sha}) =>
      TranslationModelPreset(
        id: 'test',
        name: 'Test',
        fileName: 'test.litertlm',
        url: 'http://127.0.0.1:${server.port}/m',
        sizeBytes: content.length,
        sha256: sha ?? sha256.convert(content).toString(),
        runtime: TranslationRuntime.liteRtLm,
        license: 'x',
      );

  test('downloads, verifies and installs a model', () async {
    await store.download(presetFor(body));
    final installed = await store.installed();
    expect(installed.single.fileName, 'test.litertlm');
    expect(await File(installed.single.path).readAsBytes(), body);
    expect(store.downloads, isEmpty);
    expect(File('${dir.path}/test.litertlm.part').existsSync(), isFalse);
  });

  test('an interrupted download resumes with a Range request', () async {
    dropAfter = 100000;
    await store.download(presetFor(body));
    expect(store.downloads['test']?.phase, ModelDownloadPhase.failed);
    expect(File('${dir.path}/test.litertlm.part').lengthSync(), greaterThan(0));

    await store.download(presetFor(body));
    expect(requests.last, startsWith('bytes='));
    expect(await File('${dir.path}/test.litertlm').readAsBytes(), body);
  });

  test('a checksum mismatch fails and removes the bad file', () async {
    await store.download(presetFor(body, sha: '0' * 64));
    expect(store.downloads['test']?.phase, ModelDownloadPhase.failed);
    expect(await store.installed(), isEmpty);
    expect(File('${dir.path}/test.litertlm.part').existsSync(), isFalse);
  });

  test('imports a model file and refuses other files', () async {
    final src = await File('${dir.path}/../picked.gguf').create();
    await src.writeAsBytes([1, 2, 3]);
    final model = await store.importFile(src.path);
    expect(model.runtime, TranslationRuntime.llamaCpp);
    expect((await store.installed()).map((m) => m.fileName), ['picked.gguf']);

    final bad = await File('${dir.path}/../notes.txt').create();
    expect(() => store.importFile(bad.path), throwsArgumentError);
    await src.delete();
    await bad.delete();
  });
}
