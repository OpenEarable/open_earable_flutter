import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2_led_state_reader.dart';

class LedGatt extends Fake implements BleGattManager {
  List<int> mode = [1];
  List<int> color = [12, 34, 56];

  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    expect(deviceId, 'ear');
    expect(serviceId, OpenEarableV2LedStateReader.serviceUuid);
    if (characteristicId == OpenEarableV2LedStateReader.modeUuid) return mode;
    expect(characteristicId, OpenEarableV2LedStateReader.colorUuid);
    return color;
  }
}

void main() {
  test('reads manual color, disabled output and automatic status', () async {
    final ble = LedGatt();
    final reader =
        OpenEarableV2LedStateReader(bleManager: ble, deviceId: 'ear');
    var state = await reader.readLedState();
    expect(state.showStatus, isFalse);
    expect([state.red, state.green, state.blue], [12, 34, 56]);
    expect(state.isBlack, isFalse);
    ble.color = [0, 0, 0];
    state = await reader.readLedState();
    expect(state.isBlack, isTrue);
    ble.mode = [0];
    expect((await reader.readLedState()).showStatus, isTrue);
  });

  test('rejects malformed state instead of displaying a guessed mode',
      () async {
    final ble = LedGatt();
    final reader =
        OpenEarableV2LedStateReader(bleManager: ble, deviceId: 'ear');
    for (final mode in <List<int>>[
      [],
      [0, 1],
      [2],
    ]) {
      ble.mode = mode;
      await expectLater(reader.readLedState(), throwsFormatException);
    }
    ble.mode = [1];
    ble.color = [1, 2];
    await expectLater(reader.readLedState(), throwsFormatException);
  });
}
