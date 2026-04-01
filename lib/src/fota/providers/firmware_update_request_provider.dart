import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

/// Mutable helper used by the example flow to collect firmware update inputs
/// across multiple UI steps.
class FirmwareUpdateRequestProvider extends ChangeNotifier {
  FirmwareUpdateRequest _updateParameters = FirmwareUpdateRequest();

  /// The request currently being assembled by the UI.
  FirmwareUpdateRequest get updateParameters => _updateParameters;

  /// The currently selected wearable, if any.
  Wearable? selectedWearable;

  /// Current step index in the example update wizard.
  int currentStep = 0;

  /// Selects a firmware artifact and rebuilds the request with the correct
  /// concrete request type.
  void setFirmware(SelectedFirmware? firmware) {
    if (firmware == null) {
      _updateParameters =
          FirmwareUpdateRequest(peripheral: _updateParameters.peripheral);
      return;
    }

    if (firmware is RemoteFirmware) {
      _updateParameters = MultiImageFirmwareUpdateRequest(
        peripheral: _updateParameters.peripheral,
        firmware: firmware,
      );
    } else if (firmware is LocalFirmware) {
      if (firmware.type == FirmwareType.singleImage) {
        _updateParameters = SingleImageFirmwareUpdateRequest(
          peripheral: _updateParameters.peripheral,
          firmware: firmware,
        );
      } else {
        _updateParameters = MultiImageFirmwareUpdateRequest(
          peripheral: _updateParameters.peripheral,
          firmware: firmware,
        );
      }
    }

    notifyListeners();
  }

  /// Selects the wearable that should receive the update.
  void setSelectedPeripheral(Wearable wearable) {
    selectedWearable = wearable;
    _updateParameters.peripheral = SelectedPeripheral(
      name: wearable.name,
      identifier: wearable.deviceId,
    );
    notifyListeners();
  }

  /// Clears the current request and resets the wizard state.
  void reset() {
    _updateParameters = FirmwareUpdateRequest();
    currentStep = 0;
    notifyListeners();
  }

  /// Advances the example wizard by one step.
  void nextStep() {
    if (currentStep == 1) {
      return;
    }
    currentStep++;
    notifyListeners();
  }

  /// Moves the example wizard one step backwards.
  void previousStep() {
    if (currentStep == 0) {
      return;
    }
    currentStep--;
    notifyListeners();
  }
}
