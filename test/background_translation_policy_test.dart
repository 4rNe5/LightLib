// When library translation may run, and how long it rests.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/translation/background_translation_notice.dart';
import 'package:openlib/services/translation/book_translation_service.dart';

void main() {
  BookTranslationWait reason(DeviceLoad load,
          {bool reading = false,
          bool canRunNow = true,
          bool chargingOnly = false,
          bool priority = false,
          bool fullSpeed = false,
          bool cooling = false}) =>
      backgroundWaitReason(
          load: load,
          reading: reading,
          canRunNow: canRunNow,
          chargingOnly: chargingOnly,
          priority: priority,
          fullSpeed: fullSpeed,
          cooling: cooling);

  test('waits for the reader, the app, heat, battery and the charger', () {
    const ok = DeviceLoad(battery: 80);
    expect(reason(ok), BookTranslationWait.none);
    expect(reason(ok, reading: true), BookTranslationWait.reading);
    expect(reason(ok, canRunNow: false), BookTranslationWait.appClosed);
    // Warmth only slows it down (see the rest below); it stops when
    // severe throttling is near, by status or by headroom.
    expect(reason(const DeviceLoad(thermal: 1)), BookTranslationWait.none);
    expect(reason(const DeviceLoad(thermal: 2)), BookTranslationWait.none);
    expect(reason(const DeviceLoad(thermal: 3)), BookTranslationWait.warm);
    expect(reason(const DeviceLoad(headroom: 1.02)), BookTranslationWait.warm);
    expect(reason(const DeviceLoad(headroom: 0.95)), BookTranslationWait.none);
    // Once stopped, it waits until the phone has cooled a little.
    expect(reason(const DeviceLoad(headroom: 0.95), cooling: true),
        BookTranslationWait.warm);
    expect(reason(const DeviceLoad(thermal: 2), cooling: true),
        BookTranslationWait.none);
    expect(
        reason(const DeviceLoad(battery: 15)), BookTranslationWait.batteryLow);
    expect(reason(const DeviceLoad(battery: 15, charging: true)),
        BookTranslationWait.none);
    expect(reason(const DeviceLoad(powerSave: true)),
        BookTranslationWait.powerSave);
    expect(reason(ok, chargingOnly: true), BookTranslationWait.needsCharger);
    expect(reason(const DeviceLoad(charging: true), chargingOnly: true),
        BookTranslationWait.none);
  });

  test('a book chosen to go first: only heat, the app and an empty battery',
      () {
    const ok = DeviceLoad(battery: 80);
    expect(reason(ok, reading: true, priority: true), BookTranslationWait.none);
    expect(reason(ok, chargingOnly: true, priority: true),
        BookTranslationWait.none);
    expect(reason(const DeviceLoad(powerSave: true), priority: true),
        BookTranslationWait.none);
    expect(reason(const DeviceLoad(battery: 15), priority: true),
        BookTranslationWait.none);
    expect(reason(const DeviceLoad(battery: 8), priority: true),
        BookTranslationWait.batteryLow);
    expect(reason(const DeviceLoad(battery: 8, charging: true), priority: true),
        BookTranslationWait.none);
    expect(reason(const DeviceLoad(thermal: 3), priority: true),
        BookTranslationWait.warm);
    expect(reason(ok, canRunNow: false, priority: true),
        BookTranslationWait.appClosed);
    // With the app open: like reading, until the phone is about to shut
    // down for heat.
    full(DeviceLoad load) =>
        reason(load, reading: true, priority: true, fullSpeed: true);
    expect(full(const DeviceLoad(thermal: 3)), BookTranslationWait.none);
    expect(full(const DeviceLoad(headroom: 1.2)), BookTranslationWait.none);
    expect(full(const DeviceLoad(battery: 3, powerSave: true)),
        BookTranslationWait.none);
    expect(full(const DeviceLoad(thermal: 4)), BookTranslationWait.warm);
    // fullSpeed alone (not the chosen book) changes nothing.
    expect(reason(const DeviceLoad(thermal: 3), fullSpeed: true),
        BookTranslationWait.warm);
  });

  test('rests by heat: little while cool, more as the phone warms', () {
    const took = Duration(seconds: 2);
    expect(backgroundRest(took, DeviceLoad.nominal), const Duration(seconds: 1));
    expect(backgroundRest(took, const DeviceLoad(charging: true)),
        const Duration(milliseconds: 500));
    expect(backgroundRest(took, const DeviceLoad(thermal: 1)),
        const Duration(seconds: 2));
    expect(backgroundRest(took, const DeviceLoad(thermal: 2)),
        const Duration(seconds: 4));
    expect(backgroundRest(took, const DeviceLoad(headroom: 0.93)),
        const Duration(seconds: 6));
    expect(backgroundRest(Duration.zero, DeviceLoad.nominal),
        const Duration(milliseconds: 300));
    expect(backgroundRest(const Duration(minutes: 1), DeviceLoad.nominal),
        const Duration(seconds: 30));
    // A book chosen to go first rests only once the phone is warm.
    expect(backgroundRest(took, DeviceLoad.nominal, priority: true),
        Duration.zero);
    expect(backgroundRest(took, const DeviceLoad(thermal: 1), priority: true),
        Duration.zero);
    expect(backgroundRest(took, const DeviceLoad(thermal: 2), priority: true),
        const Duration(seconds: 1));
    expect(
        backgroundRest(took, const DeviceLoad(headroom: 0.95), priority: true),
        const Duration(seconds: 3));
    expect(
        backgroundRest(took, const DeviceLoad(thermal: 3),
            priority: true, fullSpeed: true),
        Duration.zero);
  });

  test('device readings from the platform map', () {
    final load = DeviceLoad.fromMap({
      'thermal': 3,
      'powerSave': true,
      'battery': 42,
      'charging': false,
      'headroom': 0.7,
    });
    expect(load.headroom, 0.7);
    // Severe status counts as hot whatever the headroom says.
    expect(load.heat, 1.0);
    expect(DeviceLoad.fromMap({'headroom': -1.0}).headroom, isNull);
    expect(const DeviceLoad(headroom: 0.7).heat, 0.7);
    expect(const DeviceLoad(thermal: 2, headroom: 0.4).heat, 0.85);
    expect(load.thermal, 3);
    expect(load.powerSave, isTrue);
    expect(load.battery, 42);
    expect(load.charging, isFalse);
    expect(DeviceLoad.fromMap({}).battery, 100);
  });
}
