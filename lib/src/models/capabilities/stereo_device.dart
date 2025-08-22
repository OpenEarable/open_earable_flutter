enum DevicePosition {
  left,
  right
}

abstract class StereoDevice {
  Future<DevicePosition?> get position;
  Future<StereoDevice?> get pairedDevice;

  Future<void> pair(StereoDevice device);
  Future<void> unpair();
}
