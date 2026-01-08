import 'dart:ui';

import '../../managers/wearable_disconnect_notifier.dart';

abstract class Wearable {
  final String name;

  final List<dynamic> _capabilities = [];

  Wearable({
    required this.name,
    required WearableDisconnectNotifier disconnectNotifier,
  }) {
    disconnectNotifier.addListener(_notifyDisconnectListeners);
    _capabilities.add(this);
  }

  bool hasCapability<T>() {
    for (final capability in _capabilities) {
      if (capability is T) {
        return true;
      }
    }
    return false;
  }

  T? getCapability<T>() {
    for (final capability in _capabilities) {
      if (capability is T) {
        return capability;
      }
    }
    return null;
  }

  T requireCapability<T>() {
    final capability = getCapability<T>();
    if (capability != null) {
      return capability;
    }
    throw StateError('Wearable does not have required capability: $T');
  }

  void registerCapability<T>(T capability) {
    if (hasCapability<T>()) {
      throw StateError('Wearable already has capability: $T');
    }
    _capabilities.add(capability);
  }

  /// Gets path to an icon representing the wearable.
  /// Preferred type is SVG.
  /// Needs to be added to the asset section of the pubspec.yaml file.
  /// When setting the path here, keep in mind it's a lib
  /// ('packages/open_earable_flutter/assets/...').
  ///
  /// The parameters are best-effort
  ///
  /// @param darkmode: Whether the icon should be for dark mode (if available).
  String? getWearableIconPath({bool darkmode = false}) {
    return null;
  }

  final List<VoidCallback> _disconnectListeners = [];

  void addDisconnectListener(VoidCallback listener) {
    _disconnectListeners.add(listener);
  }

  void _notifyDisconnectListeners() {
    for (final listener in _disconnectListeners) {
      listener.call();
    }
  }

  String get deviceId;

  Future<void> disconnect();
}
