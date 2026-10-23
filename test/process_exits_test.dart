// Which earlier exits count as the app failing.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/process_exits.dart';

ProcessExit exit(String reason, {int importance = 100}) =>
    ProcessExit.fromMap({
      'timestamp': 1,
      'reason': reason,
      'importance': importance,
    });

void main() {
  test('crashes count, whatever the app was doing', () {
    expect(exit('crash_native', importance: 400).likelyCrash, isTrue);
    expect(exit('crash').likelyCrash, isTrue);
    expect(exit('anr').likelyCrash, isTrue);
  });

  test('killed on screen counts, reclaimed in the background does not', () {
    expect(exit('low_memory', importance: 100).likelyCrash, isTrue);
    expect(exit('signaled', importance: 125).likelyCrash, isTrue);
    expect(exit('low_memory', importance: 400).likelyCrash, isFalse);
    expect(exit('other', importance: 400).likelyCrash, isFalse);
  });

  test('the user closing the app does not', () {
    expect(exit('user_requested').likelyCrash, isFalse);
    expect(exit('user_stopped').likelyCrash, isFalse);
    expect(exit('exit_self').likelyCrash, isFalse);
  });

  test('reads what Android reports', () {
    final e = ProcessExit.fromMap({
      'timestamp': 1792760000000,
      'reason': 'crash_native',
      'description': 'crash',
      'pssKb': 123,
      'trace': 'libLiteRtOpenClAccelerator.so',
    });
    expect(e.timestamp.millisecondsSinceEpoch, 1792760000000);
    expect(e.metadata['pssKb'], 123);
    expect(e.trace, contains('OpenCl'));
  });
}
