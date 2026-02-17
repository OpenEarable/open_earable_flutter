import '../wearable_factory.dart';

/// This capability indicates whether the device is connected via the system's
/// bluetooth management, for example the settings app.
abstract class SystemDevice {
  bool get isConnectedViaSystem;
}

/// A [SystemDevice] that can be updated after connection metadata is enriched.
abstract class MutableSystemDevice extends SystemDevice {
  void setConnectedViaSystem(bool isConnectedViaSystem);
}

class ConnectedViaSystem extends ConnectionOption {
  const ConnectedViaSystem();
}
