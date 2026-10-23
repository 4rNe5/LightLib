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
          bool chargingOnly = false}) =>
      backgroundWaitReason(
          load: load,
          reading: reading,
          canRunNow: canRunNow,
          chargingOnly: chargingOnly);

  test('waits for the reader, the app, heat, battery and the charger', () {
    const ok = DeviceLoad(battery: 80);
    expect(reason(ok), BookTranslationWait.none);
    expect(reason(ok, reading: true), BookTranslationWait.reading);
    expect(reason(ok, canRunNow: false), BookTranslationWait.appClosed);
    expect(reason(const DeviceLoad(thermal: 2)), BookTranslationWait.warm);
    // Light warmth only slows it down (see the rest below).
    expect(reason(const DeviceLoad(thermal: 1)), BookTranslationWait.none);
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

  test('rests longer than it works, longer still when warm', () {
    const took = Duration(seconds: 2);
    expect(
        backgroundRest(took, DeviceLoad.nominal), const Duration(seconds: 3));
    expect(backgroundRest(took, const DeviceLoad(charging: true)),
        const Duration(seconds: 2));
    expect(backgroundRest(took, const DeviceLoad(thermal: 1)),
        const Duration(seconds: 6));
    expect(backgroundRest(Duration.zero, DeviceLoad.nominal),
        const Duration(milliseconds: 300));
    expect(backgroundRest(const Duration(minutes: 1), DeviceLoad.nominal),
        const Duration(seconds: 30));
  });

  test('device readings from the platform map', () {
    final load = DeviceLoad.fromMap(
        {'thermal': 3, 'powerSave': true, 'battery': 42, 'charging': false});
    expect(load.thermal, 3);
    expect(load.powerSave, isTrue);
    expect(load.battery, 42);
    expect(load.charging, isFalse);
    expect(DeviceLoad.fromMap({}).battery, 100);
  });
}
