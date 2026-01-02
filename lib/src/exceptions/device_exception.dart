sealed class DeviceException implements Exception {
  const DeviceException();
}

class UnsupportedDeviceException extends DeviceException {
  const UnsupportedDeviceException();
}

class AlreadyConnectedException extends DeviceException {
  const AlreadyConnectedException();
}

class ConnectionFailedException extends DeviceException {
  const ConnectionFailedException();
}
