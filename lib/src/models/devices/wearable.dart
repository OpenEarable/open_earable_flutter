import 'dart:async';
import 'dart:ui';

import '../../managers/wearable_disconnect_notifier.dart';

enum WearableIconVariant {
  single,
  left,
  right,
  pair,
}

abstract class Wearable {
  final String name;

  final Map<Type, Object> _capabilities = {};

  final StreamController<List<Type>> _registeredCapabilityController =
      StreamController<List<Type>>.broadcast();

  Wearable({
    required this.name,
    required WearableDisconnectNotifier disconnectNotifier,
  }) {
    disconnectNotifier.addListener(_notifyDisconnectListeners);
  }

  /// Checks if the wearable has a specific capability.
  bool hasCapability<T>() {
    if (_capabilities.containsKey(T)) {
      return true;
    }
    return this is T;
  }

  /// Gets a specific capability of the wearable.
  /// Returns null if the capability is not supported by this wearable.
  T? getCapability<T>() {
    if (_capabilities.containsKey(T)) {
      return _capabilities[T] as T;
    }
    if (this is T) {
      return this as T;
    }
    return null;
  }

  /// Gets a specific capability of the wearable, throwing a StateError if not supported.
  T requireCapability<T>() {
    final capability = getCapability<T>();
    if (capability != null) {
      return capability;
    }
    throw StateError('Wearable does not have required capability: $T');
  }

  /// Registers a specific capability for the wearable.
  /// Throws a StateError if the capability is already registered.
  void registerCapability<T>(T capability) {
    if (hasCapability<T>()) {
      throw StateError('Wearable already has capability: $T');
    }
    _capabilities[T] = capability as Object;
    _registeredCapabilityController.add([T]);
  }

  /// Stream that emits an event whenever a new capability is registered.
  Stream<List<Type>> get capabilityRegistered => _registeredCapabilityController.stream;

  Stream<void> capabilityAvailable<T>() async* {
    final cap = getCapability<T>();
    if (cap != null) {
      yield cap;
      return;
    }

    await for (final _ in capabilityRegistered) {
      final next = getCapability<T>();
      if (next != null) {
        yield next;
        return;
      }
    }
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
  /// @param variant: Which icon variant should be used.
  String? getWearableIconPath({
    bool darkmode = false,
    WearableIconVariant variant = WearableIconVariant.single,
  }) {
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
