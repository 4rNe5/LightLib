// What sync's progress bar and notifications say.

// Flutter imports:
import 'package:flutter/widgets.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/sync/sync_engine.dart';
import 'package:openlib/services/sync/sync_service.dart';

void main() {
  final ko = lookupAppLocalizations(const Locale('ko'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('progress: the stage, its count and the book', () {
    expect(
        syncProgressText(
            ko,
            const SyncProgress(SyncStage.downloading,
                done: 3, total: 18, title: '春の駅')),
        '책 받는 중 3/18 · 春の駅');
    expect(syncProgressText(en, const SyncProgress(SyncStage.checking)),
        'Checking what changed…');
    expect(
        syncProgressText(
            en, const SyncProgress(SyncStage.translations, done: 1, total: 6)),
        'Translations 1/6');
  });

  test('summary: what moved, or that nothing had to', () {
    final report = SyncReport()
      ..uploaded = 18
      ..translationsSent = 19362
      ..glossariesSent = 4;
    expect(syncSummaryText(ko, report),
        '책 ↑18 ↓0 · 위치 ↑0 ↓0 · 번역 ↑19362 ↓0 · 용어집 ↑4 ↓0');
    expect(syncSummaryText(ko, SyncReport()), '모두 최신 상태입니다.');
  });

  test('transfers: only stages that move something', () {
    expect(const SyncProgress(SyncStage.checking).transfers, isFalse);
    expect(const SyncProgress(SyncStage.translations).transfers, isFalse);
    expect(const SyncProgress(SyncStage.uploading, total: 2).transfers, isTrue);
  });
}
