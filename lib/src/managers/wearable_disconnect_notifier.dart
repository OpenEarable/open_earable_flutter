import 'dart:ui';

class WearableDisconnectNotifier {
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
}
