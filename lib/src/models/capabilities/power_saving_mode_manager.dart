/// Manages firmware-defined power saving modes.
///
/// Implementations read the supported mode list from the wearable so apps can
/// show newly added firmware modes without package or app changes.
abstract class PowerSavingModeManager {
  /// Reads all power saving modes supported by the wearable.
  Future<List<PowerSavingMode>> readSupportedPowerSavingModes();

  /// Reads the currently selected power saving mode.
  Future<PowerSavingMode> readPowerSavingMode();

  /// Applies [mode] as the current power saving mode.
  Future<void> setPowerSavingMode(PowerSavingMode mode);
}

/// A selectable firmware-defined power saving mode.
class PowerSavingMode {
  /// Stable firmware-defined mode identifier.
  final int id;

  /// User-facing mode name supplied by the firmware.
  final String name;

  /// Creates a power saving mode.
  const PowerSavingMode({required this.id, required this.name});

  @override
  bool operator ==(Object other) {
    return other is PowerSavingMode && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return name;
  }
}
